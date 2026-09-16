defmodule Jido.AgentServer.RuntimeBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ParentRef
  alias Jido.AgentServer.Signal.Error, as: ErrorSignal
  alias Jido.Error
  alias Jido.Tracing.Trace
  alias JidoTest.AgentFixtures

  @moduletag capture_log: true

  defmodule EmitMany do
    use Jido.Action, name: "runtime_boundary_emit_many"

    def run(%{count: count}, %{agent_state: state}) do
      signal = Jido.Signal.new!("boundary.output", %{}, source: "/boundary")
      directives = List.duplicate(Directive.emit(signal, {:noop, []}), count)
      {:ok, %{state | count: state.count + 1}, directives}
    end
  end

  defmodule Agent do
    use Jido.Agent, name: "runtime_boundary_agent"

    agent do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "boundary.fail", AgentFixtures.Fail
      route "jido.agent.error", AgentFixtures.Fail
      route "boundary.emit", EmitMany
      route "boundary.hold", AgentFixtures.BlockingAdd
    end
  end

  defmodule BlockingDispatchAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def options_schema do
      Zoi.keyword(
        [observer: Zoi.pid() |> Zoi.required(), gate: Zoi.any() |> Zoi.required()],
        unrecognized_keys: :error
      )
    end

    @impl true
    def deliver(signal, opts) do
      observer = Keyword.fetch!(opts, :observer)
      gate = Keyword.fetch!(opts, :gate)
      send(observer, {:error_signal_delivery_blocked, gate, self(), signal})

      receive do
        {:release_error_signal_delivery, ^gate} -> :ok
      end
    end
  end

  test "Jido.Exec execution can exceed the Directive timeout", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        directive_timeout: 50,
        restart: :temporary
      )

    gate = make_ref()
    test_pid = self()

    caller =
      Task.async(fn ->
        Server.call(
          server,
          signal("boundary.hold", %{
            by: 1,
            label: "slow",
            test_pid: test_pid,
            gate: gate
          })
        )
      end)

    assert_receive {:agent_action_blocked, ^gate, worker}, 2_000
    Process.send_after(worker, {:release, gate}, 100)

    assert {:ok, %{state: %{count: 1, history: ["slow"]}}} = Task.await(caller, 2_000)
    assert Server.status(server).phase == :idle
  end

  test "a waiting custom policy can query its Server while later Signals and stop run", %{
    jido: jido
  } do
    test = self()
    gate = make_ref()
    {:ok, holder} = Elixir.Agent.start_link(fn -> nil end)
    on_exit(fn -> if Process.alive?(holder), do: Elixir.Agent.stop(holder) end)

    policy = fn _error, _outcome ->
      server = Elixir.Agent.get(holder, & &1)
      send(test, {:policy_started, self()})
      send(test, {:policy_own_status, Server.status(server).phase})

      receive do
        {:release_policy, ^gate} -> :continue
      end
    end

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        error_policy: policy,
        directive_timeout: 2_000,
        restart: :temporary
      )

    :ok = Elixir.Agent.update(holder, fn _ -> server end)
    assert {:error, _reason} = Server.call(server, signal("boundary.fail"))
    assert_receive {:policy_started, policy_owner}, 1_000
    assert_receive {:policy_own_status, :idle}, 1_000
    assert Server.status(server).phase == :idle
    assert {:ok, _agent} = Server.call(server, signal("boundary.emit", %{count: 1}))
    assert Process.alive?(policy_owner)

    monitor = Process.monitor(server)
    assert :ok = Server.stop(server, :shutdown, 500)
    assert_receive {:DOWN, ^monitor, :process, ^server, :shutdown}, 1_000
  end

  test "a custom policy timeout stops its owned task and Server", %{jido: jido} do
    test = self()

    policy = fn _error, _outcome ->
      send(test, {:policy_blocked, self()})

      receive do
        :never -> :continue
      end
    end

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        error_policy: policy,
        directive_timeout: 50,
        restart: :temporary
      )

    monitor = Process.monitor(server)
    assert {:error, _reason} = Server.call(server, signal("boundary.fail"))
    assert_receive {:policy_blocked, policy_owner}, 1_000

    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, {:error_policy_timeout, 50}}},
                   1_000

    eventually(fn -> not Process.alive?(policy_owner) end)
  end

  test "error Signal policy reports failure without causing a feedback loop", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, error_policy: {:emit_signal, {:pid, target: self()}})

    original = Server.snapshot(server)
    trace = Map.put(Trace.new_root(), :tracestate, "vendor=value")
    assert {:ok, input} = Trace.put(signal("boundary.fail"), trace)
    assert {:error, reason} = Server.call(server, input)
    assert_receive {:signal, error_signal}
    assert error_signal.type == ErrorSignal.type()
    assert error_signal.source == "/agent/#{original.agent.id}"
    assert {:ok, validated} = ErrorSignal.validate_data(error_signal.data)
    assert validated == error_signal.data
    assert error_signal.data.agent_id == original.agent.id
    assert error_signal.data.error == Error.to_map(reason)
    assert error_signal.data.stage == :execute
    refute error_signal.data.committed?
    assert Jido.Signal.get_context(error_signal, "jidocausationid") == input.id
    emitted_trace = Trace.get(error_signal)
    assert emitted_trace.trace_id == trace.trace_id
    assert emitted_trace.tracestate == trace.tracestate
    refute emitted_trace.span_id == trace.span_id
    assert Server.snapshot(server) == original

    assert {:error, _} = Server.call(server, error_signal)
    refute_received {:signal, _}
    assert Server.snapshot(server) == original
  end

  test "error Signals report invalid input without requiring its ID or trace", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, error_policy: {:emit_signal, {:pid, target: self()}})

    for invalid_id <- [nil, 42, true, "", <<255>>] do
      input = %{signal("boundary.fail") | id: invalid_id}
      assert {:error, reason} = Server.call(server, input)
      assert_receive {:signal, error_signal}

      assert error_signal.type == ErrorSignal.type()
      assert error_signal.data.stage == :prepare
      assert error_signal.data.error == Error.to_map(reason)
      assert Jido.Signal.get_context(error_signal, "jidocausationid") == nil
      assert Trace.get(error_signal) == nil
      assert Server.status(server).phase == :idle
    end
  end

  test "invalid input IDs do not break the trace carried by error Signals", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, error_policy: {:emit_signal, {:pid, target: self()}})

    trace = Trace.new_root()
    trace_id = trace.trace_id
    assert {:ok, input} = Trace.put(signal("boundary.fail"), trace)

    for invalid_id <- [42, true, "", <<255>>] do
      assert {:error, _reason} = Server.call(server, %{input | id: invalid_id})
      assert_receive {:signal, error_signal}
      assert Jido.Signal.get_context(error_signal, "jidocausationid") == nil

      emitted_trace = Trace.get(error_signal)

      assert %{trace_id: ^trace_id} =
               Trace.child_of(emitted_trace, Map.get(emitted_trace, :causation_id))
    end
  end

  test "error Signal delivery is bounded and does not block control calls", %{jido: jido} do
    gate = make_ref()
    dispatch = {BlockingDispatchAdapter, observer: self(), gate: gate}

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        error_policy: {:emit_signal, dispatch},
        directive_timeout: 50,
        debug: true
      )

    input = signal("boundary.fail")
    assert {:error, _reason} = Server.call(server, input)
    assert_receive {:error_signal_delivery_blocked, ^gate, worker, error_signal}, 2_000
    assert error_signal.type == "jido.agent.error"
    assert Jido.Signal.get_context(error_signal, "jidocausationid") == input.id
    assert %{trace_id: _trace_id} = Trace.get(error_signal)
    worker_ref = Process.monitor(worker)

    assert Server.status(server).phase == :idle
    assert {:error, :idle} = Server.cancel(server)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000

    events =
      eventually(fn ->
        case Server.recent_events(server) do
          {:ok, events} ->
            if Enum.any?(events, &(&1.event == :error_signal_delivery_failed)), do: events

          _other ->
            nil
        end
      end)

    event = Enum.find(events, &(&1.event == :error_signal_delivery_failed))
    assert %{type: :timeout, retryable?: true} = event.metadata.error
    refute is_struct(event.metadata.error)
    assert Process.alive?(server)
  end

  test "shutdown stops a pending error Signal delivery", %{jido: jido} do
    gate = make_ref()
    dispatch = {BlockingDispatchAdapter, observer: self(), gate: gate}

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        error_policy: {:emit_signal, dispatch},
        directive_timeout: 10_000,
        restart: :temporary
      )

    assert {:error, _reason} = Server.call(server, signal("boundary.fail"))
    assert_receive {:error_signal_delivery_blocked, ^gate, worker, _signal}, 2_000
    worker_ref = Process.monitor(worker)
    server_ref = Process.monitor(server)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^server_ref, :process, ^server, _reason}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
  end

  test "abrupt owner death stops a pending error Signal delivery", %{jido: jido} do
    gate = make_ref()
    dispatch = {BlockingDispatchAdapter, observer: self(), gate: gate}

    {:ok, server} =
      Jido.start_agent(jido, Agent,
        error_policy: {:emit_signal, dispatch},
        directive_timeout: 10_000,
        restart: :temporary
      )

    assert {:error, _reason} = Server.call(server, signal("boundary.fail"))
    assert_receive {:error_signal_delivery_blocked, ^gate, worker, _signal}, 2_000
    assert worker in Task.Supervisor.children(Jido.task_supervisor_name(jido))
    assert server in elem(Process.info(worker, :links), 1)

    server_ref = Process.monitor(server)
    worker_ref = Process.monitor(worker)
    Process.exit(server, :kill)

    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
  end

  test "invalid and raised policy results stop the Server with a structured reason", %{jido: jido} do
    for {policy, expected} <- [
          {fn _, _ -> :invalid end, {:invalid_error_policy_result, :invalid}},
          {fn _, _ -> raise "policy failed" end,
           {:error_policy_failed, %RuntimeError{message: "policy failed"}}}
        ] do
      {:ok, server} = Jido.start_agent(jido, Agent, error_policy: policy, restart: :temporary)
      ref = Process.monitor(server)
      assert {:error, _} = Server.call(server, signal("boundary.fail"))
      assert_receive {:DOWN, ^ref, :process, ^server, {:shutdown, ^expected}}
    end
  end

  test "Directive count limits reject the candidate before commit", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, max_directives_per_turn: 1, directive_timeout: :infinity)

    original = Server.snapshot(server)

    assert {:error, {:too_many_directives, %{count: 2, limit: 1}}} =
             Server.call(server, signal("boundary.emit", %{count: 2}))

    assert Server.snapshot(server) == original
    assert {:ok, committed} = Server.call(server, signal("boundary.emit", %{count: 1}))
    eventually(fn -> Server.status(server).phase == :idle end)
    assert committed.state.count == 1
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "named Servers support liveness checks and remove names on stop", %{jido: jido} do
    for name <- [
          {:global, {__MODULE__, jido}},
          Server.via_tuple("named-boundary", Jido.registry_name(jido)),
          Module.concat(jido, BoundaryAgent)
        ] do
      server = start_supervised!({Server, agent: Agent, name: name})
      assert Server.alive?(server)
      assert Server.alive?(name)
      assert :ok = Server.await_ready(name)
      assert :ok = Server.stop(server)
      refute Server.alive?(server)
      refute Server.alive?(name)
      assert {:error, :not_running} = Server.await_ready(server)
    end
  end

  test "idle cancellation and invalid control requests keep the Agent usable", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, debug: true)
    original = Server.snapshot(server)
    assert {:error, :idle} = Server.cancel(server)
    assert {:error, :unknown_call} = :gen_statem.call(server, :unsupported)
    :gen_statem.cast(server, :unsupported)
    assert {:ok, []} = Server.recent_events(server, limit: :invalid)

    assert {:error, {:adopt_child_failed, :child_not_found}} =
             Server.adopt_child(server, "missing", :child)

    parent = ParentRef.new!(pid: server, id: original.agent.id, tag: :self)
    assert {:error, :cannot_adopt_self} = Server.adopt_parent(server, parent)
    assert Server.snapshot(server) == original
  end

  test "startup rejects invalid Exec options, limits, names and missing persistence", %{
    jido: jido
  } do
    for opts <- [
          [exec_module: String],
          [exec_opts: :invalid],
          [exec_opts: [:invalid]],
          [max_postponed_signals: -1],
          [max_directives_per_turn: -1]
        ] do
      assert {:error, _} = Jido.start_agent(jido, Agent, opts)
    end

    assert {:error, :jido_instance_required} = Server.start(agent: Agent)
    assert {:error, _} = Jido.start_agent(jido, Agent, persistence: nil, restore: :required)

    assert {:error, %Jido.Error.ValidationError{message: message}} =
             Server.start_link(agent: Agent, name: 123)

    assert message =~ "name is invalid"
  end

  test "public parent adoption and hibernation return structured errors", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent)
    invalid_parent = %ParentRef{pid: :invalid, id: "parent", tag: :worker}

    assert {:error, %Jido.Error.ValidationError{message: "Agent parent reference is invalid"}} =
             Server.adopt_parent(server, invalid_parent)

    assert {:error, :not_running} = Server.hibernate(:missing_agent_server)
    assert Process.alive?(server)
  end
end
