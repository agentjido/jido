defmodule Jido.Examples.Topology.HierarchyTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Hierarchy
  alias Jido.Topology.Controller

  test "owned workers stay stopped after their leader restarts", %{jido: jido} do
    controller =
      start_supervised!(
        {Controller,
         jido: jido, topology: Hierarchy.new!(id: "hierarchy-example"), repair: :manual}
      )

    assert :ok = Controller.await_ready(controller)
    leader = Controller.whereis_agent(controller, :leader)
    coordinator = Controller.whereis_agent(controller, :coordinator)
    workers = for index <- 1..3, do: Controller.whereis_agent(controller, :workers, index)
    assert map_size(Server.children(leader)) == 3
    assert Jido.agent_count(jido) == 5

    monitors = monitor_runtime([leader | workers])
    Process.exit(leader, :kill)
    assert_down(monitors)

    eventually(fn ->
      replacement = Controller.whereis_agent(controller, :leader)
      is_pid(replacement) and replacement != leader
    end)

    replacement = Controller.whereis_agent(controller, :leader)
    assert :ok = Controller.reconcile(controller)

    eventually(fn ->
      status = Controller.status(controller)

      status.active == 0 and
        status.errors == Map.new(1..3, &{"group/workers/#{&1}", :member_stopped})
    end)

    assert Controller.whereis_agent(controller, :coordinator) == coordinator
    assert Server.status(replacement).runtime.parent.pid == coordinator
    assert Server.children(coordinator)["agent/leader"].pid == replacement
    assert Server.children(replacement) == %{}
    for index <- 1..3, do: assert(Controller.whereis_agent(controller, :workers, index) == nil)
    stop_topology(controller, [coordinator, replacement])
    assert Jido.agent_count(jido) == 0
  end
end
