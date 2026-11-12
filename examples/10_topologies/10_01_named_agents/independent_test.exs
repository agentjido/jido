Code.require_file("cell.ex", __DIR__)
Code.require_file("independent.ex", __DIR__)

defmodule Jido.Examples.Topology.IndependentTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  import Jido.Test.AgentServer.TopologyAssertions
  alias Jido.Examples.Topology.Independent
  alias Independent.Cell

  test "a JSON definition starts the same declared members", %{jido: jido} do
    definition = Jido.Examples.Topology.Independent.definition()
    registry = Independent.registry()
    assert %Jido.Catalog{} = registry
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(definition, registry)

    assert {:ok, decoded} =
             Jido.Test.AgentServer.Registry.decode(
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert decoded == definition
    server = start_topology(jido, decoded)

    assert Enum.sort(Enum.map(members(server), &Jido.AgentServer.snapshot(&1).agent.state.label)) ==
             [
               "left",
               "right"
             ]

    [left] = labeled(server, "left")

    assert {:ok, %{cron: %{}}} =
             Jido.Test.AgentServer.ExampleRuntime.plugin_state(left, Jido.Plugin.Scheduler)

    {:ok, schedule} = Cell.schedule_signal(%{value: 4})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(left, schedule)

      assert turn_result.status in [:committed, :waiting]
    )

    eventually(fn -> Jido.AgentServer.snapshot(left).agent.state.total == 4 end)
    assert Jido.AgentServer.snapshot(left).agent.state.received == 1
    stop_topology(server)
  end

  test "named members keep separate initial and committed state", %{jido: jido} do
    server = start_topology(jido, Independent)
    [left] = labeled(server, "left")
    [right] = labeled(server, "right")
    assert Jido.resident_agent_count(jido) == 3
    assert Jido.AgentServer.snapshot(left).agent.id != Jido.AgentServer.snapshot(right).agent.id
    before = Jido.AgentServer.snapshot(right)

    assert {:ok, work} = Cell.work_signal(%{value: 4})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(left, work)

      assert turn_result.status in [:committed, :waiting]
      changed = Jido.AgentServer.snapshot(left).agent
    )

    assert Map.take(changed.state, [:label, :received, :total]) == %{
             label: "left",
             received: 1,
             total: 4
           }

    assert Jido.AgentServer.snapshot(right) == before
    stop_topology(server)
    assert Jido.resident_agent_count(jido) == 0
  end

  test "stopping the owner stops all member runtimes", %{jido: jido} do
    server = start_topology(jido, Independent)
    assert length(members(server)) == 2
    stop_topology(server)
    assert Jido.resident_agent_count(jido) == 0
  end
end
