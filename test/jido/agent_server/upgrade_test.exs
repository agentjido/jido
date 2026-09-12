defmodule JidoTest.AgentServer.UpgradeTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server

  defmodule BlockingAction do
    use Jido.Action, name: "upgrade_test_blocking_action"

    def run(_input, context) do
      :atomics.put(context.marker, 1, 1)
      send(context.observer, {:turn_blocked, context.gate, self()})

      receive do
        {:release, gate} when gate == context.gate ->
          :atomics.put(context.marker, 1, 2)
          {:ok, %{value: 1}}
      end
    end
  end

  defmodule SourceAgent do
    use Jido.Agent, name: "upgrade_test_source"

    agent do
      schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "upgrade.block", BlockingAction
    end
  end

  defmodule SetValueAction do
    use Jido.Action,
      name: "upgrade_test_set_value",
      schema: Zoi.object(%{value: Zoi.string()})

    def run(%{value: value}, context) do
      {:ok, %{context.agent_state | value: value}}
    end
  end

  defmodule TargetAgent do
    use Jido.Agent, name: "upgrade_test_target", vsn: 2

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
    end

    routes do
      route "upgrade.set", SetValueAction
    end
  end

  defmodule FinalAgent do
    use Jido.Agent, name: "upgrade_test_final", vsn: 3

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
    end
  end

  defmodule DifferentPlugin do
    use Jido.Plugin

    def state_spec(_opts), do: {:extra, Zoi.integer() |> Zoi.default(0)}
  end

  defmodule PluginTargetAgent do
    use Jido.Agent, name: "upgrade_test_plugin_target", vsn: 2

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
      plugin DifferentPlugin
    end
  end

  defmodule PersistentJido do
    use Jido,
      otp_app: :jido,
      namespace: "jido/test/agent-server-upgrade",
      persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  test "a quiescent operation runs after the active Turn finishes", c do
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: unique_id("quiescent"))
    marker = :atomics.new(1, [])
    gate = make_ref()
    observer = self()

    turn =
      Task.async(fn ->
        Server.call(server, signal("upgrade.block"),
          context: %{marker: marker, observer: observer, gate: gate}
        )
      end)

    assert_receive {:turn_blocked, ^gate, worker}, 1_000

    upgrade =
      Task.async(fn ->
        Server.upgrade(server, fn ->
          send(observer, {:upgrade_marker, :atomics.get(marker, 1)})
          :ok
        end)
      end)

    send(worker, {:release, gate})
    assert {:ok, %{state: %{value: 1}}} = Task.await(turn)
    assert :ok = Task.await(upgrade)
    assert_receive {:upgrade_marker, 2}, 1_000
  end

  test "a quiescent operation contains invalid results and callback faults", c do
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: unique_id("operation-errors"))

    assert {:error, :operation_failed} =
             Server.upgrade(server, fn -> {:error, :operation_failed} end)

    assert {:error, {:invalid_upgrade_result, :invalid}} =
             Server.upgrade(server, fn -> :invalid end)

    for {operation, kind} <- [
          {fn -> raise "upgrade failed" end, nil},
          {fn -> throw(:upgrade_failed) end, :throw},
          {fn -> exit(:upgrade_failed) end, :exit}
        ] do
      assert {:error, error} = Server.upgrade(server, operation)
      assert Jido.Error.code(error) == :agent_upgrade_failed

      if kind do
        assert error.details.kind == kind
        assert error.details.reason == :upgrade_failed
      else
        assert %RuntimeError{message: "upgrade failed"} = error.details.reason
      end
    end

    assert Process.alive?(server)
  end

  test "a definition upgrade validates and commits the target Agent", c do
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: unique_id("definition"))

    assert {:ok, target} =
             Server.upgrade(server, TargetAgent, fn source ->
               assert source.module == SourceAgent
               {:ok, %{value: Integer.to_string(source.state.value)}}
             end)

    assert target.module == TargetAgent
    assert target.state == %{value: "0"}
    assert Server.agent(server) == target
    assert Server.snapshot(server).state_version == 1
  end

  test "an invalid target or changed Plugin contract preserves the old snapshot", c do
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: unique_id("invalid"))
    before = Server.snapshot(server)

    assert {:error, _reason} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: :invalid}} end)

    assert Server.snapshot(server) == before

    assert {:error, :plugin_contract_changed} =
             Server.upgrade(server, PluginTargetAgent, fn _source ->
               {:ok, %{value: "0", extra: 0}}
             end)

    assert Server.snapshot(server) == before
  end

  test "definition migration rejects explicit, malformed, thrown, and exited results", c do
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: unique_id("migration-errors"))
    before = Server.snapshot(server)

    for {migration, expected} <- [
          {fn _source -> {:error, :migration_failed} end, :migration_failed},
          {fn _source -> {:ok, :invalid_state} end, {:invalid_migrated_state, :invalid_state}},
          {fn _source -> :invalid_result end, {:invalid_migration_result, :invalid_result}}
        ] do
      assert {:error, ^expected} = Server.upgrade(server, TargetAgent, migration)
      assert Server.snapshot(server) == before
    end

    for {migration, kind} <- [
          {fn _source -> throw(:migration_failed) end, :throw},
          {fn _source -> exit(:migration_failed) end, :exit}
        ] do
      assert {:error, error} = Server.upgrade(server, TargetAgent, migration)
      assert Jido.Error.code(error) == :agent_state_migration_failed
      assert error.details.kind == kind
      assert error.details.reason == :migration_failed
      assert Server.snapshot(server) == before
    end
  end

  test "definition upgrades emit bounded telemetry and debug results", c do
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:jido, :agent, :definition_upgrade, :start],
          [:jido, :agent, :definition_upgrade, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(owner, {:definition_upgrade, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    id = unique_id("observed")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id, debug: true)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "ready"}} end)

    assert_receive {:definition_upgrade, [:jido, :agent, :definition_upgrade, :start],
                    %{state_version_before: 0},
                    %{
                      agent_id: ^id,
                      agent_module: SourceAgent,
                      target_agent_module: TargetAgent
                    }}

    assert_receive {:definition_upgrade, [:jido, :agent, :definition_upgrade, :stop],
                    %{
                      duration: duration,
                      state_version_before: 0,
                      state_version_after: 1
                    },
                    %{
                      agent_id: ^id,
                      agent_module: SourceAgent,
                      target_agent_module: TargetAgent,
                      status: :ok
                    }}

    assert duration >= 0
    before_failure = Server.snapshot(server)

    assert {:error, error} =
             Server.upgrade(server, FinalAgent, fn _source -> raise "migration failed" end)

    assert Jido.Error.code(error) == :agent_state_migration_failed
    assert Server.snapshot(server) == before_failure

    assert_receive {:definition_upgrade, [:jido, :agent, :definition_upgrade, :start],
                    %{state_version_before: 1},
                    %{
                      agent_id: ^id,
                      agent_module: TargetAgent,
                      target_agent_module: FinalAgent
                    }}

    assert_receive {:definition_upgrade, [:jido, :agent, :definition_upgrade, :stop],
                    %{duration: failure_duration, state_version_before: 1} = measurements,
                    %{
                      agent_id: ^id,
                      agent_module: TargetAgent,
                      target_agent_module: FinalAgent,
                      status: :error,
                      error_code: :agent_state_migration_failed
                    }}

    assert failure_duration >= 0
    refute Map.has_key?(measurements, :state_version_after)

    assert {:ok,
            [
              %{event: :definition_upgrade_failed, metadata: failure},
              %{event: :definition_upgrade_completed, metadata: success}
            ]} = Server.recent_events(server)

    assert success == %{
             status: :ok,
             agent_module: SourceAgent,
             target_agent_module: TargetAgent,
             state_version_before: 0,
             state_version_after: 1
           }

    assert %{
             status: :error,
             agent_module: TargetAgent,
             target_agent_module: FinalAgent,
             state_version_before: 1,
             state_version_after: nil,
             error: %{details: %{code: :agent_state_migration_failed}}
           } = failure
  end

  test "an in-instance checkpoint restores the upgraded definition after a crash", c do
    id = unique_id("restart")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "saved"}} end)

    replacement = restart_after_kill(c.jido, id, server)

    assert Server.agent(replacement).module == TargetAgent
    assert Server.agent(replacement).state == %{value: "saved"}
    assert Server.snapshot(replacement).state_version == 1
  end

  test "an in-instance checkpoint keeps the initial definition across multiple upgrades", c do
    id = unique_id("multi-restart")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "middle"}} end)

    assert {:ok, %{module: FinalAgent}} =
             Server.upgrade(server, FinalAgent, fn source ->
               assert source.module == TargetAgent
               {:ok, %{value: source.state.value <> "-final"}}
             end)

    replacement = restart_after_kill(c.jido, id, server)

    assert Server.agent(replacement).module == FinalAgent
    assert Server.agent(replacement).state == %{value: "middle-final"}
    assert Server.snapshot(replacement).state_version == 2
  end

  test "a commit after an upgrade keeps the initial definition recovery lineage", c do
    id = unique_id("commit-restart")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "upgraded"}} end)

    assert {:ok, %{state: %{value: "committed"}}} =
             Server.call(server, signal("upgrade.set", %{value: "committed"}))

    replacement = restart_after_kill(c.jido, id, server)

    assert Server.agent(replacement).module == TargetAgent
    assert Server.agent(replacement).state == %{value: "committed"}
    assert Server.snapshot(replacement).state_version == 2
  end

  test "a namespaced durable record changes definition in one revision" do
    start_supervised!(PersistentJido)
    id = unique_id("durable")
    {:ok, server} = PersistentJido.start_agent(SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "saved"}} end)

    assert :ok = PersistentJido.hibernate(server)
    assert {:ok, replacement} = PersistentJido.thaw(TargetAgent, id)
    assert Server.agent(replacement).state == %{value: "saved"}
    assert Server.snapshot(replacement).state_version == 1
  end

  test "a durable definition upgrade keeps its persistence reason" do
    start_supervised!(PersistentJido)
    id = unique_id("durable-observation")
    {:ok, server} = PersistentJido.start_agent(SourceAgent, id: id)
    handler = {__MODULE__, make_ref()}
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :persistence, :operation, :stop],
        fn event, measurements, metadata, _config ->
          send(owner, {:persistence, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "saved"}} end)

    assert_receive {:persistence, [:jido, :persistence, :operation, :stop],
                    %{duration: duration, revision_after: 1},
                    %{
                      agent_id: ^id,
                      agent_module: TargetAgent,
                      operation: :compare_and_swap,
                      persistence_reason: :definition_upgrade,
                      status: :ok
                    }}

    assert duration >= 0
  end

  test "a durable same-definition upgrade uses the normal save path" do
    start_supervised!(PersistentJido)
    id = unique_id("durable-same-definition")
    {:ok, server} = PersistentJido.start_agent(SourceAgent, id: id)

    assert {:ok, %{module: SourceAgent, state: %{value: 42}}} =
             Server.upgrade(server, SourceAgent, fn _source -> {:ok, %{value: 42}} end)

    assert :ok = PersistentJido.hibernate(server)
    assert {:ok, replacement} = PersistentJido.thaw(SourceAgent, id)
    assert Server.snapshot(replacement) == %{agent: Server.agent(replacement), state_version: 1}
    assert Server.agent(replacement).state == %{value: 42}
  end

  defp restart_after_kill(jido, id, server) do
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000

    eventually(fn ->
      case Jido.whereis_agent(jido, id) do
        pid when is_pid(pid) and pid != server -> pid
        _other -> false
      end
    end)
  end
end
