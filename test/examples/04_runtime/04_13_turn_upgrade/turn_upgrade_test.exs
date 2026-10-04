defmodule JidoTest.Examples.Runtime.TurnUpgradeAction do
  @moduledoc false
  use Jido.Action,
    name: "test_runtime_turn_upgrade_action",
    schema: Zoi.object(%{block: Zoi.boolean() |> Zoi.default(false)})

  alias JidoTest.Examples.TurnUpgradeBarrier, as: Barrier

  def run(%{block: true}, context), do: record_release(context, Barrier.wait())

  def run(%{block: false}, context), do: record_release(context, Barrier.current())

  defp record_release(context, release) do
    state = context.agent_state
    {:ok, %{state | releases: state.releases ++ [release]}}
  end
end

defmodule JidoTest.Examples.Runtime.TurnUpgradeAgent do
  @moduledoc false
  use Jido.Agent, name: "test_runtime_turn_upgrade_agent"

  agent do
    schema Zoi.object(%{releases: Zoi.list(Zoi.integer()) |> Zoi.default([])})
  end

  routes do
    signal_source "/test/examples/runtime/turn_upgrade"

    route "test.examples.runtime.turn_upgrade.run",
          JidoTest.Examples.Runtime.TurnUpgradeAction
  end
end

defmodule JidoTest.Examples.Runtime.TurnUpgradeTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.Examples.TurnUpgrade
  alias JidoTest.Examples.TurnUpgradeBarrier, as: Barrier
  alias JidoTest.Examples.Runtime.TurnUpgradeAgent

  setup do
    start_supervised!(Barrier)
    :ok
  end

  test "an idle installer runs on the same Agent process", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, TurnUpgrade, id: unique_id("idle-upgrade"))
    observer = self()
    {:ok, before_signal} = TurnUpgrade.record_signal(%{release: "before"})
    assert {:ok, before} = Jido.AgentServer.call(server, before_signal)

    assert :ok =
             TurnUpgrade.install_release(server, fn ->
               send(observer, :release_installed)
               :ok
             end)

    assert_receive :release_installed, 1_000
    {:ok, after_signal} = TurnUpgrade.record_signal(%{release: "after"})
    assert {:ok, after_upgrade} = Jido.AgentServer.call(server, after_signal)
    assert after_upgrade.state.deployments == ["before", "after"]
    assert after_upgrade.id == before.id
    assert Jido.whereis_agent(jido, after_upgrade.id) == server
  end

  test "the installer waits for an active Turn before later work", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, TurnUpgradeAgent, id: unique_id("turn-upgrade"))
    :ok = Barrier.arm(self())

    active =
      Task.async(fn ->
        Jido.AgentServer.call(server, turn_signal(true))
      end)

    assert_receive :turn_blocked, 1_000

    upgrade =
      Task.async(fn ->
        TurnUpgrade.install_release(server, fn ->
          Barrier.install(2)
        end)
      end)

    assert :ok = Barrier.release()
    assert {:ok, first} = Task.await(active)
    assert first.state.releases == [1]
    assert :ok = Task.await(upgrade)

    assert {:ok, second} = Jido.AgentServer.call(server, turn_signal(false))

    assert second.state.releases == [1, 2]
    assert Jido.whereis_agent(jido, second.id) == server
  end

  defp turn_signal(block) do
    Jido.Signal.new!(
      "test.examples.runtime.turn_upgrade.run",
      %{block: block},
      source: "/test/examples/runtime/turn_upgrade"
    )
  end
end
