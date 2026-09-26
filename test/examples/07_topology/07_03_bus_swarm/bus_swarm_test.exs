defmodule Jido.Examples.Topology.BusSwarmTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag timeout: 120_000
  alias Jido.Examples.Topology.{Cell, Formats}
  alias Jido.Topology.{Codec, Controller}

  test "boots 1000 Bus workers from a stored JSON definition" do
    jido = :"topology_scale_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido, max_tasks: 4096})
    {:ok, json} = Formats.json()
    {:ok, instance} = Codec.decode(JSON.decode!(json), Formats.registry(), id: "large")
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller, 90000)
    assert %{agents: 1001, resources: 1, status: :ready} = Controller.status(controller)
    assert Jido.agent_count(jido) == 1001
    bus = Controller.whereis_bus(controller, :work)

    {:ok, command_signal_1} = Cell.work_signal(%{value: 1})

    assert {:ok, [_]} =
             Jido.Signal.Bus.publish(bus, [command_signal_1])

    workers =
      for index <- 1..1000 do
        Controller.whereis_agent(controller, :workers, index)
      end

    eventually(fn -> Enum.all?(workers, &(Jido.AgentServer.agent(&1).state.total == 1)) end,
      timeout: 20000
    )

    Supervisor.stop(controller)
    eventually(fn -> Jido.agent_count(jido) == 0 end, timeout: 10000)
  end
end
