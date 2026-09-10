defmodule JidoTest.Examples.TurnUpgradePipeline do
  @moduledoc false
  use Jido.Flow, name: "test_turn_upgrade_pipeline"

  flow do
    step "first",
      action: Jido.Examples.TurnUpgrade.Step,
      params: %{total: 0, revisions: []}

    step "barrier", action: JidoTest.Examples.TurnUpgradeBarrier, params: result("first")
    step "second", action: Jido.Examples.TurnUpgrade.Step, params: result("barrier")
    output result("second")
  end
end

defmodule JidoTest.Examples.TurnUpgradeAgent do
  @moduledoc false
  use Jido.Agent, name: "test_turn_upgrade_agent"

  agent do
    schema Zoi.object(%{
             total: Zoi.integer() |> Zoi.default(0),
             revisions: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/test/examples/turn_upgrade"
    route "test.examples.turn_upgrade.run", JidoTest.Examples.TurnUpgradePipeline
  end

  def run(server, context) do
    Jido.AgentServer.call(
      server,
      Jido.Signal.new!(
        "test.examples.turn_upgrade.run",
        %{},
        source: "/test/examples/turn_upgrade"
      ),
      context: context
    )
  end
end

defmodule JidoTest.Examples.TurnUpgradeTest do
  use JidoTest.Case, async: false
  @moduletag :example
  alias Jido.Examples.TurnUpgrade, as: Example
  alias Jido.AgentServer, as: Server

  setup %{jido: jido} do
    :ok = Example.install_step(1)
    {:ok, server} = Jido.start_agent(jido, Example, id: unique_id("upgrade"), restart: :temporary)

    on_exit(fn -> Example.install_step(1) end)

    %{server: server}
  end

  test "without a deployment both Flow steps use revision 1", c do
    assert {:ok, agent} = Example.run(c.server)
    assert agent.state == %{total: 2, revisions: [1, 1]}
    assert Server.snapshot(c.server).state_version == 1
  end

  test "loading code while idle changes real behavior on the same Agent PID", c do
    assert {:ok, before} = Example.run(c.server)
    :ok = Example.install_step(2)
    assert {:ok, after_load} = Example.run(c.server)
    assert before.state.total == 2
    assert after_load.state == %{total: 20, revisions: [2, 2]}
    assert after_load.id == before.id
    assert Jido.whereis_agent(c.jido, before.id) == c.server
  end

  test "an active Turn finishes on its old revision before the next Turn uses new code", c do
    alias JidoTest.Examples.TurnUpgradeAgent, as: BlockingAgent

    {:ok, server} =
      Jido.start_agent(c.jido, BlockingAgent,
        id: unique_id("blocking-upgrade"),
        restart: :temporary
      )

    gate = make_ref()
    observer = self()
    caller = Task.async(fn -> BlockingAgent.run(server, %{observer: observer, gate: gate}) end)
    assert_receive {:between_upgrade_steps, ^gate, worker}, 2_000
    assert Server.snapshot(server).state_version == 0

    upgrade = Task.async(fn -> Server.upgrade(server, fn -> Example.install_step(2) end) end)
    send(worker, {:release, gate})
    assert {:ok, active} = Task.await(caller)
    assert :ok = Task.await(upgrade)
    assert {:ok, next} = BlockingAgent.run(server, %{})

    assert next.state == %{total: 20, revisions: [2, 2]}
    assert Server.snapshot(server).state_version == 2
    assert Jido.whereis_agent(c.jido, active.id) == server
    assert active.state == %{total: 2, revisions: [1, 1]}
  end
end
