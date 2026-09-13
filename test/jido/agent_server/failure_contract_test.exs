defmodule Jido.AgentServer.FailureContractTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Error.ExecutionError
  alias JidoTest.AgentFixtures

  defmodule Agent do
    use Jido.Agent,
      name: "server_failure_contract",
      schema:
        Zoi.object(%{
          count: Zoi.integer() |> Zoi.default(0),
          history: Zoi.list(Zoi.string()) |> Zoi.default([])
        }),
      routes: [
        {"counter.add", AgentFixtures.Add},
        {"counter.block", AgentFixtures.BlockingAdd},
        {"counter.fail", AgentFixtures.Fail}
      ]
  end

  defmodule ControlledStorage do
    @behaviour Jido.Persistence.Adapter

    def validate_options(opts), do: Jido.Persistence.ETS.validate_options(opts)
    defdelegate get(key, opts), to: Jido.Persistence.ETS
    defdelegate put(key, value, opts), to: Jido.Persistence.ETS
    defdelegate delete(key, opts), to: Jido.Persistence.ETS

    def compare_and_swap(key, expected, value, opts) do
      case Elixir.Agent.get(Keyword.fetch!(opts, :control), & &1) do
        :ok -> Jido.Persistence.ETS.compare_and_swap(key, expected, value, opts)
        {:error, _reason} = error -> error
      end
    end
  end

  defmodule ObservedExec do
    def run_async(executable, input, context, opts) do
      {observer, opts} = Keyword.pop!(opts, :observer)
      handle = Jido.Exec.run_async(executable, input, context, opts)
      send(observer, {:exec_owner, self(), handle.pid})
      handle
    end

    defdelegate handle_message(handle, message), to: Jido.Exec
    defdelegate cancel(handle), to: Jido.Exec
  end

  defmodule FailedCancelExec do
    defdelegate run_async(executable, input, context, opts), to: ObservedExec
    defdelegate handle_message(handle, message), to: Jido.Exec
    def cancel(_handle), do: {:error, :cancel_refused}
  end

  defmodule HeldReadyPlugin do
    use Jido.Plugin

    def child_spec(_init) do
      Supervisor.child_spec({Elixir.Agent, fn -> nil end}, id: __MODULE__)
    end

    def await_ready(_runtime, opts) do
      send(Keyword.fetch!(opts, :observer), {:readiness_waiting, self()})

      receive do
        :release_readiness -> :ok
      end
    end
  end

  defmodule FailedDispatch do
    @behaviour Jido.Signal.Dispatch.Adapter

    def options_schema do
      Zoi.keyword(
        [observer: Zoi.pid() |> Zoi.required(), mode: Zoi.atom() |> Zoi.required()],
        unrecognized_keys: :error
      )
    end

    def deliver(signal, opts) do
      send(Keyword.fetch!(opts, :observer), {:error_delivery, self(), signal})

      case Keyword.fetch!(opts, :mode) do
        :error -> {:error, :delivery_refused}
        :kill -> Process.exit(self(), :kill)
      end
    end
  end

  test "upgrade operation failures preserve the complete committed snapshot", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, idle_timeout: 60_000)
    before = Server.snapshot(server)

    assert {:error, :install_refused} =
             Server.upgrade(server, fn -> {:error, :install_refused} end)

    assert {:error, {:invalid_upgrade_result, :invalid}} =
             Server.upgrade(server, fn -> :invalid end)

    assert {:error,
            %ExecutionError{
              message: "Agent upgrade operation failed",
              details: %{code: :agent_upgrade_failed, reason: %RuntimeError{message: "install"}}
            }} = Server.upgrade(server, fn -> raise "install" end)

    for kind <- [:throw, :exit] do
      assert {:error,
              %ExecutionError{
                details: %{code: :agent_upgrade_failed, kind: ^kind, reason: :install_refused}
              }} = Server.upgrade(server, fn -> :erlang.raise(kind, :install_refused, []) end)

      assert Server.snapshot(server) == before
    end

    assert Server.status(server).runtime.lifecycle.idle_timer?
    assert :ok = Server.upgrade(server, fn -> :ok end)
    assert Server.snapshot(server) == before
  end

  test "migration failures return structured errors and retain the source definition", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, Agent)
    before = Server.snapshot(server)

    for state <- [:invalid, before.agent] do
      assert {:error, {:invalid_migrated_state, ^state}} =
               Server.upgrade(server, Agent, fn _ -> {:ok, state} end)

      assert Server.snapshot(server) == before
    end

    assert {:error, :migration_refused} =
             Server.upgrade(server, Agent, fn _ -> {:error, :migration_refused} end)

    assert {:error, {:invalid_migration_result, :invalid}} =
             Server.upgrade(server, Agent, fn _ -> :invalid end)

    assert {:error,
            %ExecutionError{
              message: "Agent state migration failed",
              details: %{
                code: :agent_state_migration_failed,
                reason: %RuntimeError{message: "migration"}
              }
            }} = Server.upgrade(server, Agent, fn _ -> raise "migration" end)

    for kind <- [:throw, :exit] do
      assert {:error,
              %ExecutionError{
                details: %{
                  code: :agent_state_migration_failed,
                  kind: ^kind,
                  reason: :migration_refused
                }
              }} =
               Server.upgrade(server, Agent, fn _ ->
                 :erlang.raise(kind, :migration_refused, [])
               end)

      assert Server.snapshot(server) == before
    end

    assert Server.agent(server).module == Agent
    assert Server.status(server).phase == :idle
  end

  test "a durable upgrade of the same module writes one complete revision", %{jido: jido} do
    {persistence, _control} = storage()
    {:ok, server} = Jido.start_agent(jido, Agent, persistence: persistence)
    before = Server.agent(server)

    assert {:ok, upgraded} =
             Server.upgrade(server, Agent, fn source ->
               assert source == before
               {:ok, %{count: 7, history: ["migration"]}}
             end)

    assert upgraded == %{before | state: %{count: 7, history: ["migration"]}}
    assert Server.snapshot(server) == %{agent: upgraded, state_version: 1}

    assert {:ok, ^upgraded, 1} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, before.id,
               instance: jido
             )
  end

  test "a failed durable upgrade stops the activation and preserves the stored revision", %{
    jido: jido
  } do
    {persistence, control} = storage()
    {:ok, server} = Jido.start_agent(jido, Agent, persistence: persistence)
    before = Server.agent(server)
    monitor = Process.monitor(server)
    Elixir.Agent.update(control, fn _ -> {:error, :storage_unavailable} end)

    assert {:error, {:persistence_failed, {:indeterminate, :storage_unavailable}}} =
             Server.upgrade(server, Agent, fn _ -> {:ok, %{count: 9, history: ["rejected"]}} end)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:shutdown, {:persistence_failed, {:indeterminate, :storage_unavailable}}}},
                   1_000

    assert {:ok, ^before, 0} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, before.id,
               instance: jido
             )

    assert Jido.whereis_agent(jido, before.id) == nil
  end

  test "failed hibernation preserves the live snapshot and permits a later retry", %{jido: jido} do
    {persistence, control} = storage()
    {:ok, server} = Jido.start_agent(jido, Agent, persistence: persistence)
    before = Server.snapshot(server)
    Elixir.Agent.update(control, fn _ -> {:error, :storage_unavailable} end)

    assert {:error, {:indeterminate, :storage_unavailable}} = Server.hibernate(server)
    assert Server.snapshot(server) == before
    assert Server.status(server).phase == :idle

    Elixir.Agent.update(control, fn _ -> :ok end)
    assert :ok = Server.hibernate(server)
    refute Process.alive?(server)

    assert {:ok, restored, 0} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, before.agent.id,
               instance: jido
             )

    assert restored == before.agent
  end

  test "hibernation rejects absent storage and unavailable process references", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent)
    before = Server.snapshot(server)

    assert {:error, :persistence_not_configured} = Server.hibernate(server)
    assert Server.snapshot(server) == before
    assert :ok = Server.stop(server)
    assert {:error, :not_running} = Server.hibernate(server)
    assert {:error, :not_running} = Server.hibernate({:invalid, make_ref()})
    assert {:error, :not_running} = Server.hibernate({:global, make_ref()})
  end

  test "a hibernation wait timeout does not cancel the active Turn", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent)
    before = Server.snapshot(server)
    {request, worker, gate} = block_turn(server)

    assert {:error, :timeout} = Server.hibernate(server, timeout: 0)
    assert Server.snapshot(server) == before
    assert Server.status(server).phase == :running

    send(worker, {:release, gate})
    assert {:reply, {:ok, committed}} = Server.receive_response(request)
    assert committed.state == %{count: 1, history: ["held"]}
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    assert Server.status(server).phase == :idle
  end

  test "stale Plugin lifecycle messages cannot replace the current child", %{jido: jido} do
    definition = %{Agent.definition() | plugins: [{HeldReadyPlugin, [observer: self()]}]}
    server = start_supervised!({Server, agent: definition, jido: jido, register: false})
    assert_receive {:readiness_waiting, readiness}, 1_000
    send(readiness, :release_readiness)
    assert :ok = Server.await_ready(server)
    children = Server.children(server)
    before = Server.snapshot(server)
    token = make_ref()

    send(server, {:plugin_runtime_restarting, self(), HeldReadyPlugin})
    send(server, {:plugin_runtime_ready, self(), HeldReadyPlugin, self()})
    send(server, {:plugin_runtime_bootstrap, self(), HeldReadyPlugin, token})

    assert_receive {:plugin_runtime_bootstrap, ^token,
                    {:error, {:stale_plugin_runtime_bootstrap, HeldReadyPlugin}}},
                   1_000

    assert Server.children(server) == children
    assert Server.snapshot(server) == before
    assert :ok = Server.await_ready(server)
  end

  test "readiness timeout leaves a queued Signal available after readiness completes", %{
    jido: jido
  } do
    definition = %{Agent.definition() | plugins: [{HeldReadyPlugin, [observer: self()]}]}
    server = start_supervised!({Server, agent: definition, jido: jido, register: false})
    assert_receive {:readiness_waiting, readiness}, 1_000
    assert {:error, :timeout} = Server.await_ready(server, 0)

    request = Server.send_request(server, signal("counter.add", %{by: 2, label: "ready"}))
    assert %{phase: :initializing, admission: %{postponed: 1}} = Server.status(server)
    send(readiness, :release_readiness)

    assert {:reply, {:ok, committed}} = Server.receive_response(request)
    assert committed.state == %{count: 2, history: ["ready"]}
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
    assert :ok = Server.await_ready(server)
  end

  test "loss of the readiness worker stops initialization", %{jido: jido} do
    definition = %{Agent.definition() | plugins: [{HeldReadyPlugin, [observer: self()]}]}

    server =
      start_supervised!(
        {Server, agent: definition, jido: jido, register: false, restart: :temporary}
      )

    assert_receive {:readiness_waiting, readiness}, 1_000
    monitor = Process.monitor(server)
    Process.exit(readiness, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^server,
                    {:shutdown, {:plugin_readiness_failed, :killed}}},
                   1_000

    assert {:error, :not_running} = Server.await_ready(server)
  end

  test "an Exec owner exit fails the Turn without changing committed state", %{jido: jido} do
    {:ok, server} =
      Jido.start_agent(jido, Agent, exec_module: ObservedExec, exec_opts: [observer: self()])

    before = Server.snapshot(server)
    {request, worker, _gate} = block_turn(server)
    assert_receive {:exec_owner, owner, root}, 1_000
    worker_ref = Process.monitor(worker)
    root_ref = Process.monitor(root)
    Process.exit(owner, :kill)

    assert {:reply,
            {:error,
             %ExecutionError{
               message: "Agent Exec adapter owner exited",
               details: %{
                 code: :agent_exec_callback_task_failed,
                 module: ObservedExec,
                 reason: :killed
               }
             }}} = Server.receive_response(request)

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 1_000
    assert_receive {:DOWN, ^root_ref, :process, ^root, _reason}, 1_000
    assert Server.snapshot(server) == before
    assert %{phase: :idle, active: nil} = Server.status(server)
  end

  for entry <- [:call, :cast] do
    test "failed timeout cancellation stops a #{entry} Turn and its owned work", %{jido: jido} do
      {:ok, server} =
        Jido.start_agent(jido, Agent,
          exec_module: FailedCancelExec,
          exec_opts: [observer: self()],
          turn_timeout: 60_000,
          restart: :temporary
        )

      gate = make_ref()
      input = signal("counter.block", %{test_pid: self(), gate: gate, by: 1, label: "timeout"})
      monitor = Process.monitor(server)

      request =
        case unquote(entry) do
          :call -> Server.send_request(server, input)
          :cast -> Server.cast(server, input)
        end

      assert_receive {:exec_owner, owner, root}, 1_000
      assert_receive {:agent_action_blocked, ^gate, worker}, 1_000
      owner_ref = Process.monitor(owner)
      root_ref = Process.monitor(root)
      worker_ref = Process.monitor(worker)

      assert {:running, %{active: active}} = :sys.get_state(server)
      assert is_integer(Process.cancel_timer(active.timeout_timer))
      send(server, {:timeout, active.timeout_timer, {:turn_timeout, active.turn_id}})

      if unquote(entry) == :call do
        assert {:reply, {:error, {:turn_timeout_cancellation_failed, :cancel_refused}}} =
                 Server.receive_response(request)
      end

      assert_receive {:DOWN, ^monitor, :process, ^server,
                      {:shutdown, {:turn_timeout_cancellation_failed, :cancel_refused}}},
                     1_000

      assert_receive {:DOWN, ^owner_ref, :process, ^owner, _reason}, 1_000
      assert_receive {:DOWN, ^root_ref, :process, ^root, _reason}, 1_000
      assert_receive {:DOWN, ^worker_ref, :process, ^worker, _reason}, 1_000
    end
  end

  for mode <- [:error, :kill] do
    test "error Signal delivery #{mode} preserves state and records one failure", %{jido: jido} do
      {:ok, server} =
        Jido.start_agent(jido, Agent,
          error_policy: {:emit_signal, {FailedDispatch, observer: self(), mode: unquote(mode)}},
          directive_timeout: :infinity,
          debug: true
        )

      before = Server.snapshot(server)

      assert {:error,
              %Jido.Action.Error.ExecutionFailureError{
                details: %{reason: :expected_failure, retry: false}
              }} = Server.call(server, signal("counter.fail"))

      assert_receive {:error_delivery, worker, emitted}, 1_000
      assert emitted.type == "jido.agent.error"
      monitor = Process.monitor(worker)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000

      failures =
        eventually(fn ->
          {:ok, events} = Server.recent_events(server)
          failures = Enum.filter(events, &(&1.event == :error_signal_delivery_failed))
          if failures != [], do: failures
        end)

      assert [%{metadata: %{error: error}}] = failures

      case unquote(mode) do
        :error ->
          assert error == Jido.Error.to_map({:emit_dispatch_failed, :delivery_refused})

        :kill ->
          assert %{
                   type: :execution_error,
                   message: "Agent error Signal delivery task exited",
                   details: %{reason: :killed}
                 } = error
      end

      assert Server.snapshot(server) == before
      assert %{phase: :idle, active: nil, runtime: %{error_count: 1}} = Server.status(server)
    end
  end

  test "a durable activation rejects a nonzero initial revision", %{jido: jido} do
    {persistence, _control} = storage()
    id = unique_id("initial-revision")

    assert {:error, {:persistence_failed, {:invalid_initial_revision, 3}}} =
             Jido.start_agent(jido, Agent,
               id: id,
               persistence: persistence,
               restore: false,
               state_version: 3
             )

    assert Jido.whereis_agent(jido, id) == nil

    assert {:error, :not_found} =
             Jido.Persistence.load_agent_with_revision(persistence, Agent, id, instance: jido)
  end

  defp block_turn(server) do
    gate = make_ref()

    request =
      Server.send_request(
        server,
        signal("counter.block", %{test_pid: self(), gate: gate, by: 1, label: "held"})
      )

    assert_receive {:agent_action_blocked, ^gate, worker}, 1_000
    {request, worker, gate}
  end

  defp storage do
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    table = :"server_failure_storage_#{System.unique_integer([:positive])}"
    {{ControlledStorage, table: table, control: control}, control}
  end
end
