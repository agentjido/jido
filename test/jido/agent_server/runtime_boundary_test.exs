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

  defmodule FailedExec do
    def run_async(_, _, _, opts) do
      case Keyword.fetch!(opts, :failure) do
        :raise -> raise "Exec unavailable"
        :throw -> throw(:exec_unavailable)
      end
    end

    def handle_message(_, _), do: :ignore
    def cancel(_), do: :ok
  end

  defmodule DelegatingExec do
    def run_async(executable, input, context, opts) do
      Jido.Exec.run_async(executable, input, context, opts)
    end

    def handle_message(handle, message), do: Jido.Exec.handle_message(handle, message)
    def cancel(handle), do: Jido.Exec.cancel(handle)
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

  defmodule BoundaryExec do
    def run_async(_executable, _input, _context, opts) do
      observer = Keyword.fetch!(opts, :observer)
      mode = Keyword.fetch!(opts, :mode)

      case mode do
        :run_raise ->
          raise "run_async failed"

        :run_throw ->
          throw(:run_async_failed)

        :run_exit ->
          exit(:run_async_failed)

        :run_invalid ->
          :invalid_handle

        :run_hang ->
          send(observer, {:exec_callback_blocked, :run_async, self()})

          receive do
            {:release_exec_callback, :run_async} -> :invalid_handle
          end

        _mode ->
          worker = spawn(fn -> wait_for_stop() end)
          send(observer, {:boundary_exec_started, self(), worker})
          %{pid: worker, observer: observer, mode: mode}
      end
    end

    def handle_message(handle, {:exec_probe, gate}) do
      send(handle.observer, {:exec_callback_started, :handle_message, gate, self()})

      case handle.mode do
        :handle_raise ->
          raise "handle_message failed"

        :handle_throw ->
          throw(:handle_message_failed)

        :handle_exit ->
          exit(:handle_message_failed)

        :handle_invalid ->
          :invalid

        :handle_hang ->
          receive do
            {:release_exec_callback, ^gate} -> :ignore
          end

        _mode ->
          :ignore
      end
    end

    def handle_message(handle, {:exec_complete, gate}) do
      send(handle.observer, {:exec_terminal_callback_started, gate, self()})

      receive do
        {:release_exec_callback, ^gate} -> {:done, {:ok, %{}}}
      end
    end

    def handle_message(_handle, _message), do: :ignore

    def cancel(handle) do
      send(handle.observer, {:exec_callback_started, :cancel, handle.mode, self()})

      case handle.mode do
        :cancel_error ->
          {:error, :cancel_failed}

        :cancel_raise ->
          raise "cancel failed"

        :cancel_throw ->
          throw(:cancel_failed)

        :cancel_exit ->
          exit(:cancel_failed)

        :cancel_invalid ->
          :invalid

        :cancel_hang ->
          receive do
            {:release_exec_callback, :cancel} -> :ok
          end

        _mode ->
          :ok
      end
    end

    defp wait_for_stop do
      receive do
        :stop -> :ok
      end
    end
  end

  test "Exec startup faults preserve the committed state", %{jido: jido} do
    for {failure, expected_kind} <- [raise: :error, throw: :throw] do
      {:ok, server} =
        Jido.start_agent(jido, Agent, exec_module: FailedExec, exec_opts: [failure: failure])

      original = Server.snapshot(server)

      assert {:error,
              %Jido.Error.ExecutionError{
                message: "Agent Exec callback failed",
                details: %{callback: :run_async, kind: kind}
              } = error} = Server.call(server, signal("boundary.emit", %{count: 1}))

      assert kind == expected_kind
      assert Error.code(error) == :agent_exec_callback_failed
      assert Server.snapshot(server) == original
      assert Server.status(server).phase == :idle
    end
  end

  test "custom Exec startup faults and hangs return structured errors", %{jido: jido} do
    for mode <- [:run_raise, :run_throw, :run_exit, :run_invalid, :run_hang] do
      {:ok, server} =
        Jido.start_agent(jido, Agent,
          exec_module: BoundaryExec,
          exec_opts: [observer: self(), mode: mode],
          directive_timeout: 50,
          restart: :temporary
        )

      original = Server.snapshot(server)
      assert {:error, error} = Server.call(server, signal("boundary.emit", %{count: 1}))

      if mode == :run_hang do
        assert_received {:exec_callback_blocked, :run_async, _owner}
        assert %Jido.Error.TimeoutError{timeout: 50} = error
        assert Error.code(error) == :agent_exec_callback_timeout
      else
        assert %Jido.Error.ExecutionError{} = error

        expected_code =
          if mode == :run_invalid,
            do: :agent_exec_invalid_callback_result,
            else: :agent_exec_callback_failed

        assert Error.code(error) == expected_code
      end

      assert Server.snapshot(server) == original
      assert Server.status(server).phase == :idle
      assert Process.alive?(server)
    end
  end

  test "a valid custom Exec execution can exceed the Directive timeout", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        exec_module: DelegatingExec,
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

  test "custom Exec message callbacks are contained, timed, and cleaned up", %{jido: jido} do
    for mode <- [:handle_raise, :handle_throw, :handle_exit, :handle_invalid, :handle_hang] do
      {:ok, server} =
        Jido.start_agent(jido, Agent,
          exec_module: BoundaryExec,
          exec_opts: [observer: self(), mode: mode],
          directive_timeout: 50,
          restart: :temporary
        )

      caller = Task.async(fn -> Server.call(server, signal("boundary.emit", %{count: 1})) end)
      assert_receive {:boundary_exec_started, _owner, worker}, 2_000
      worker_ref = Process.monitor(worker)
      gate = make_ref()
      send(server, {:exec_probe, gate})
      assert_receive {:exec_callback_started, :handle_message, ^gate, _owner}, 2_000
      assert {:error, error} = Task.await(caller, 2_000)

      if mode == :handle_hang do
        assert %Jido.Error.TimeoutError{timeout: 50} = error
        assert Error.code(error) == :agent_exec_callback_timeout
      else
        assert %Jido.Error.ExecutionError{} = error

        expected_code =
          if mode == :handle_invalid,
            do: :agent_exec_invalid_callback_result,
            else: :agent_exec_callback_failed

        assert Error.code(error) == expected_code
      end

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
      assert Server.status(server).phase == :idle
      assert Process.alive?(server)
    end
  end

  test "custom Exec cancellation preserves exact failures and bounds hangs", %{jido: jido} do
    modes = [
      {:cancel_error, :exact},
      {:cancel_raise, :structured},
      {:cancel_throw, :structured},
      {:cancel_exit, :structured},
      {:cancel_invalid, :structured},
      {:cancel_hang, :timeout}
    ]

    for {mode, expectation} <- modes do
      {:ok, server} =
        Jido.start_agent(jido, Agent,
          exec_module: BoundaryExec,
          exec_opts: [observer: self(), mode: mode],
          directive_timeout: 50,
          restart: :temporary
        )

      caller = Task.async(fn -> Server.call(server, signal("boundary.emit", %{count: 1})) end)
      assert_receive {:boundary_exec_started, _owner, worker}, 2_000
      worker_ref = Process.monitor(worker)
      server_ref = Process.monitor(server)
      assert {:error, error} = Server.cancel(server)
      assert_receive {:exec_callback_started, :cancel, ^mode, _owner}, 2_000

      case expectation do
        :exact ->
          assert error == :cancel_failed
          assert Error.code(error) == nil

        :structured ->
          assert %Jido.Error.ExecutionError{} = error

          expected_code =
            if mode == :cancel_invalid,
              do: :agent_exec_invalid_callback_result,
              else: :agent_exec_callback_failed

          assert Error.code(error) == expected_code

        :timeout ->
          assert %Jido.Error.TimeoutError{timeout: 50} = error
          assert Error.code(error) == :agent_exec_callback_timeout
      end

      assert {:error, ^error} = Task.await(caller, 2_000)

      assert_receive {:DOWN, ^server_ref, :process, ^server,
                      {:shutdown, {:exec_cancellation_failed, ^error}}},
                     2_000

      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
    end
  end

  test "custom Exec cancellation wins when terminal completion is concurrent", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        exec_module: BoundaryExec,
        exec_opts: [observer: self(), mode: :completion_race],
        directive_timeout: 2_000,
        restart: :temporary
      )

    caller = Task.async(fn -> Server.call(server, signal("boundary.emit", %{count: 1})) end)
    assert_receive {:boundary_exec_started, adapter, worker}, 2_000
    worker_ref = Process.monitor(worker)
    gate = make_ref()
    send(server, {:exec_complete, gate})
    assert_receive {:exec_terminal_callback_started, ^gate, ^adapter}, 2_000

    canceller = Task.async(fn -> Server.cancel(server) end)

    eventually(fn ->
      case Process.info(adapter, :messages) do
        {:messages, messages} ->
          Enum.any?(messages, &match?({:jido_exec_adapter_cancel, _, _, _}, &1))

        nil ->
          false
      end
    end)

    send(adapter, {:release_exec_callback, gate})

    assert :ok = Task.await(canceller, 2_000)
    assert {:error, :cancelled} = Task.await(caller, 2_000)
    assert_receive {:exec_callback_started, :cancel, :completion_race, ^adapter}, 2_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 2_000
    assert Server.status(server).phase == :idle
    assert Process.alive?(server)
  end

  test "status and stop respond while custom Exec cancellation waits", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent,
        exec_module: BoundaryExec,
        exec_opts: [observer: self(), mode: :cancel_hang],
        directive_timeout: 2_000,
        restart: :temporary
      )

    caller =
      Task.async(fn ->
        try do
          Server.call(server, signal("boundary.emit", %{count: 1}))
        catch
          :exit, reason -> {:exit, reason}
        end
      end)

    assert_receive {:boundary_exec_started, _adapter, _worker}, 2_000

    canceller =
      Task.async(fn ->
        try do
          Server.cancel(server)
        catch
          :exit, reason -> {:exit, reason}
        end
      end)

    assert_receive {:exec_callback_started, :cancel, :cancel_hang, cancel_owner}, 2_000
    assert Server.status(server).phase == :cancelling
    assert Process.alive?(cancel_owner)

    monitor = Process.monitor(server)
    assert :ok = Server.stop(server, :shutdown, 500)
    assert_receive {:DOWN, ^monitor, :process, ^server, :shutdown}, 1_000
    assert {:exit, _reason} = Task.await(canceller, 1_000)
    assert {:exit, _reason} = Task.await(caller, 1_000)
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
