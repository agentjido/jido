defmodule Jido.AgentServer.RuntimeBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ParentRef
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
              }} = Server.call(server, signal("boundary.emit", %{count: 1}))

      assert kind == expected_kind
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
      else
        assert %Jido.Error.ExecutionError{} = error
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
      else
        assert %Jido.Error.ExecutionError{} = error
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
        :exact -> assert error == :cancel_failed
        :structured -> assert %Jido.Error.ExecutionError{} = error
        :timeout -> assert %Jido.Error.TimeoutError{timeout: 50} = error
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

  test "error Signal policy reports failure without causing a feedback loop", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, error_policy: {:emit_signal, {:pid, target: self()}})

    original = Server.snapshot(server)
    assert {:error, _} = Server.call(server, signal("boundary.fail"))
    assert_receive {:signal, error_signal}
    assert error_signal.type == "jido.agent.error"
    assert error_signal.data.agent_id == original.agent.id
    assert error_signal.data.stage == :execute
    refute error_signal.data.committed?
    assert Server.snapshot(server) == original

    assert {:error, _} = Server.call(server, error_signal)
    refute_received {:signal, _}
    assert Server.snapshot(server) == original
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

    assert {:error, _reason} = Server.call(server, signal("boundary.fail"))
    assert_receive {:error_signal_delivery_blocked, ^gate, worker, error_signal}, 2_000
    assert error_signal.type == "jido.agent.error"
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
    assert %Jido.Error.TimeoutError{} = event.metadata.reason
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
