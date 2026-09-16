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

  defmodule StringAction do
    use Jido.Action, name: "upgrade_test_string_action"

    def run(_input, _context), do: {:ok, %{value: "updated"}}
  end

  defmodule TargetAgent do
    use Jido.Agent, name: "upgrade_test_target", vsn: 2

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
    end

    routes do
      route "upgrade.update", StringAction
    end
  end

  defmodule FinalAgent do
    use Jido.Agent, name: "upgrade_test_final", vsn: 3

    agent do
      schema Zoi.object(%{value: Zoi.string() |> Zoi.default("")})
    end
  end

  defmodule DifferentPlugin do
    use Jido.Plugin, agent: __MODULE__.Agent
  end

  defmodule DifferentPlugin.Agent do
    use Jido.Agent.Plugin

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

  test "an in-instance checkpoint restores the upgraded definition after a crash", c do
    id = unique_id("restart")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "saved"}} end)

    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 1_000

    replacement =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != server -> pid
          _other -> false
        end
      end)

    assert Server.agent(replacement).module == TargetAgent
    assert Server.agent(replacement).state == %{value: "saved"}
    assert Server.snapshot(replacement).state_version == 1
  end

  test "a checkpoint keeps the upgrade origin after a later Turn", c do
    id = unique_id("upgraded-turn")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "saved"}} end)

    assert {:ok, %{state: %{value: "updated"}}} =
             Server.call(server, signal("upgrade.update"))

    assert Server.snapshot(server).state_version == 2
    replacement = restart_server(c.jido, id, server)
    assert Server.agent(replacement).module == TargetAgent
    assert Server.agent(replacement).state == %{value: "updated"}
    assert Server.snapshot(replacement).state_version == 2
  end

  test "a checkpoint keeps the first upgrade origin after a second upgrade", c do
    id = unique_id("second-upgrade")
    {:ok, server} = Jido.start_agent(c.jido, SourceAgent, id: id)

    assert {:ok, %{module: TargetAgent}} =
             Server.upgrade(server, TargetAgent, fn _source -> {:ok, %{value: "first"}} end)

    assert {:ok, %{module: FinalAgent}} =
             Server.upgrade(server, FinalAgent, fn _source -> {:ok, %{value: "second"}} end)

    replacement = restart_server(c.jido, id, server)
    assert Server.agent(replacement).module == FinalAgent
    assert Server.agent(replacement).state == %{value: "second"}
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

  defp restart_server(jido, id, server) do
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
