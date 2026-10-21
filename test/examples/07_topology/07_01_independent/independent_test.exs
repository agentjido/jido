defmodule JidoTest.Examples.Topology.IndependentTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.AgentTopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Independent
  alias Independent.Cell

  test "a JSON definition starts the same declared members", %{jido: jido} do
    definition = Jido.Examples.Topology.Independent.definition()
    registry = Independent.registry()
    assert %Jido.Authoring.Registry{} = registry
    assert {:ok, document} = JidoTest.AgentRegistry.encode(definition, registry)

    assert {:ok, decoded} =
             JidoTest.AgentRegistry.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == definition
    server = start_topology(jido, decoded)

    assert Enum.sort(Enum.map(members(server), &Server.agent(&1).state.label)) == [
             "left",
             "right"
           ]

    [left] = labeled(server, "left")
    assert {:ok, %{cron: %{}}} = Server.plugin_state(left, Jido.Plugin.Scheduler)
    {:ok, schedule} = Cell.schedule_signal(%{value: 4})
    assert {:ok, _, [_]} = Server.call(left, schedule)
    eventually(fn -> Server.agent(left).state.total == 4 end)
    assert Server.agent(left).state.received == 1
    stop_topology(server)
  end

  test "named members keep separate initial and committed state", %{jido: jido} do
    server = start_topology(jido, Independent)
    [left] = labeled(server, "left")
    [right] = labeled(server, "right")
    assert Jido.agent_count(jido) == 3
    assert Server.agent(left).id != Server.agent(right).id
    before = Server.snapshot(right)

    assert {:ok, work} = Cell.work_signal(%{value: 4})
    assert {:ok, changed, []} = Server.call(left, work)

    assert Map.take(changed.state, [:label, :received, :total]) == %{
             label: "left",
             received: 1,
             total: 4
           }

    assert Server.snapshot(right) == before
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end

  test "stopping the owner stops all member runtimes", %{jido: jido} do
    server = start_topology(jido, Independent)
    assert length(members(server)) == 2
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end
end
