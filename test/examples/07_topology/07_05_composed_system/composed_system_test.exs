defmodule Jido.Examples.Topology.ComposedSystemTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, ComposedFormats}
  alias Jido.Signal.Bus
  alias Jido.Topology.{Codec, Controller, Ref}

  test "composed teams reconnect to their shared Bus after it restarts", %{jido: jido} do
    {:ok, json} = ComposedFormats.json()

    {:ok, topology} =
      Codec.decode(JSON.decode!(json), ComposedFormats.registry(), id: "composed-example")

    controller = start_supervised!({Controller, jido: jido, topology: topology, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    assert Jido.agent_count(jido) == 8
    assert %{status: :ready, resources: 1} = Controller.status(controller)
    bus = Controller.whereis_bus(controller, :events)
    assert Controller.whereis_bus(controller, Ref.ref(:east, :events)) == bus
    assert Controller.whereis_bus(controller, Ref.ref(:west, :events)) == bus

    assert {:ok, work} = Cell.work_signal(%{value: 4})
    assert {:ok, [_]} = Bus.publish(bus, [work])

    workers =
      for {team, count} <- [east: 2, west: 3], index <- 1..count do
        worker = Controller.whereis_agent(controller, Ref.ref(team, :workers), index)
        eventually(fn -> Server.agent(worker).state.total == 4 end)
        assert Server.agent(worker).state.label == Atom.to_string(team)
        worker
      end

    director = Controller.whereis_agent(controller, :director)
    east = Controller.whereis_agent(controller, Ref.ref(:east, :leader))
    west = Controller.whereis_agent(controller, Ref.ref(:west, :leader))
    assert east != west
    assert map_size(Server.children(director)) == 2
    assert map_size(Server.children(east)) == 2
    assert map_size(Server.children(west)) == 3

    assert {:ok, work} = Cell.work_signal(%{value: 9})
    assert {:ok, _} = Server.call(east, work)

    assert Server.agent(west).state.total == 0
    monitor = Process.monitor(bus)
    Process.exit(bus, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^bus, :killed}, 1_000
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_bus(controller, :events)
    assert is_pid(replacement) and replacement != bus
    assert Controller.whereis_bus(controller, Ref.ref(:east, :events)) == replacement
    assert Controller.whereis_bus(controller, Ref.ref(:west, :events)) == replacement
    agents = [director, east, west | workers]

    for agent <- agents, do: assert(Jido.whereis_agent(jido, Server.agent(agent).id) == agent)
    assert {:ok, work} = Cell.work_signal(%{value: 5})
    assert {:ok, [_]} = Bus.publish(replacement, [work])

    for worker <- workers do
      eventually(fn -> Server.snapshot(worker).state_version == 2 end)
      assert Server.agent(worker).state.total == 9
      assert Server.agent(worker).state.received == 2
    end

    assert Server.agent(east).state == %{label: "east", received: 1, total: 9}
    assert Server.agent(west).state == %{label: "west", received: 0, total: 0}
    stop_topology(controller, agents, [replacement])
    assert Jido.agent_count(jido) == 0
  end
end
