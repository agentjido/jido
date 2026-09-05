defmodule Jido.Examples.Topology.ComposedSystemTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, ComposedFormats}
  alias Jido.Signal.Bus
  alias Jido.Topology.{Codec, Controller, Ref}

  test "boots two composed teams from JSON with one shared Bus", %{jido: jido} do
    {:ok, json} = ComposedFormats.json()

    {:ok, topology} =
      Codec.decode(JSON.decode!(json), ComposedFormats.registry(), id: "composed-example")

    controller = start_supervised!({Controller, jido: jido, topology: topology})
    assert :ok = Controller.await_ready(controller)
    assert Jido.agent_count(jido) == 8
    assert %{status: :ready, resources: 1} = Controller.status(controller)
    bus = Controller.whereis_bus(controller, :events)
    assert Controller.whereis_bus(controller, Ref.ref(:east, :events)) == bus
    assert Controller.whereis_bus(controller, Ref.ref(:west, :events)) == bus
    assert {:ok, [_]} = Bus.publish(bus, [Cell.work_signal!(4)])

    workers =
      for {team, count} <- [{:east, 2}, {:west, 3}], index <- 1..count do
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
    assert {:ok, _} = Cell.work(east, 9)
    assert Server.agent(west).state.total == 0
    assert Process.alive?(bus)
    Supervisor.stop(controller)

    eventually(fn ->
      Enum.all?(workers, &(not Process.alive?(&1))) and not Process.alive?(bus)
    end)
  end
end
