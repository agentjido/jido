defmodule Jido.Topology.ControllerTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, Hierarchy, Independent, Swarm}
  alias Jido.Signal.Bus
  alias Jido.Topology.{Builder, Controller}

  test "invalid repair policy fails before topology activation", %{jido: jido} do
    assert {:error, %Jido.Error.ValidationError{}} =
             Controller.start_link(
               jido: jido,
               topology: Independent.new!(id: "invalid-repair"),
               repair: :sometimes
             )

    assert Jido.agent_count(jido) == 0
  end

  test "starts independent agents, preserves committed state, and cleans up", %{jido: jido} do
    controller =
      start_supervised!({Controller, jido: jido, topology: Independent.new!(id: "independent")})

    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)
    assert Server.agent(left).state.label == "left"
    assert Server.agent(right).state.label == "right"
    assert {:ok, _} = Cell.work(left, 3)

    assert {:error, {:already_started, ^controller}} =
             Controller.start_link(jido: jido, topology: Independent.new!(id: "independent"))

    assert Server.agent(left).state.total == 3
    Supervisor.stop(controller)
    eventually(fn -> not Process.alive?(left) and not Process.alive?(right) end)
  end

  test "establishes logical ownership for nested groups", %{jido: jido} do
    controller = start_supervised!({Controller, jido: jido, topology: Hierarchy.new!(id: "tree")})
    assert :ok = Controller.await_ready(controller)
    coordinator = Controller.whereis_agent(controller, :coordinator)
    leader = Controller.whereis_agent(controller, :leader)
    assert Server.children(coordinator)["agent/leader"].pid == leader
    assert map_size(Server.children(leader)) == 3
    worker = Controller.whereis_agent(controller, :workers, "1")

    assert {:ok, %{parent_id: "tree/agent/leader"}} =
             Jido.agent_parent_binding(jido, Server.agent(worker).id)
  end

  test "broadcasts each Signal to every member", %{jido: jido} do
    instance = Swarm.new!(id: "swarm", input: %{worker_count: 4})
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :work)
    assert {:ok, [_]} = Bus.publish(bus, [Cell.work_signal!(7)])

    for index <- 1..4 do
      worker = Controller.whereis_agent(controller, :workers, index)
      eventually(fn -> Server.agent(worker).state.total == 7 end)
    end

    assert %{status: :ready, agents: 5, resources: 1, errors: %{}} = Controller.status(controller)
  end

  test "supports more than one Bus subscription on an Agent", %{jido: jido} do
    instance =
      Builder.new(name: "multiple")
      |> Builder.agent(:cell, Cell)
      |> Builder.bus(:a)
      |> Builder.bus(:b)
      |> Builder.subscribe(:cell, to: :a, path: "topology.work")
      |> Builder.subscribe(:cell, to: :b, path: "topology.work")
      |> Builder.build!(id: "multiple")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    for key <- [:a, :b],
        do:
          assert(
            {:ok, [_]} =
              Bus.publish(Controller.whereis_bus(controller, key), [Cell.work_signal!(2)])
          )

    agent = Controller.whereis_agent(controller, :cell)
    eventually(fn -> Server.agent(agent).state.total == 4 end)
  end

  test "repairs an agent after a normal stop", %{jido: jido} do
    instance =
      Builder.new(Independent)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: "repair")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    old = Controller.whereis_agent(controller, :left)
    :ok = Jido.stop_agent(jido, old)

    eventually(
      fn ->
        new = Controller.whereis_agent(controller, :left)
        is_pid(new) and new != old and Process.alive?(new)
      end,
      timeout: 2_000
    )
  end

  test "repairs parent bindings after parent failure", %{jido: jido} do
    instance =
      Builder.new(Hierarchy)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: "repair-tree")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    old = Controller.whereis_agent(controller, :leader)
    Process.exit(old, :kill)

    eventually(
      fn ->
        new = Controller.whereis_agent(controller, :leader)
        is_pid(new) and new != old and map_size(Server.children(new)) == 3
      end,
      timeout: 5_000
    )
  end

  test "reports identity conflicts and never stops an unrelated agent", %{jido: jido} do
    {:ok, existing} = Jido.start_agent(jido, Cell, id: "conflict/agent/left")

    controller =
      start_supervised!({Controller, jido: jido, topology: Independent.new!(id: "conflict")})

    eventually(fn ->
      Controller.status(controller).errors["agent/left"] == :agent_identity_in_use
    end)

    Supervisor.stop(controller)
    assert Process.alive?(existing)
  end

  test "readiness can succeed after an earlier caller times out", %{jido: jido} do
    {:ok, existing} = Jido.start_agent(jido, Cell, id: "waiting/agent/left")

    instance =
      Builder.new(Independent)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: "waiting")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    eventually(fn -> Controller.status(controller).status == :degraded end)
    assert catch_exit(Controller.await_ready(controller, 10))
    :ok = Jido.stop_agent(jido, existing)
    assert :ok = Controller.await_ready(controller, 2_000)
  end

  test "scopes Buses and agents to the topology instance", %{jido: jido} do
    controllers =
      for id <- ["one", "two"] do
        controller =
          start_supervised!(
            {Controller, jido: jido, topology: Swarm.new!(id: id, input: %{worker_count: 1})}
          )

        assert :ok = Controller.await_ready(controller)
        controller
      end

    [first, second] = controllers
    assert Controller.whereis_bus(first, :work) != Controller.whereis_bus(second, :work)

    assert Controller.whereis_agent(first, :workers, 1) !=
             Controller.whereis_agent(second, :workers, 1)
  end

  defmodule PersistentJido do
    use Jido, otp_app: :jido, persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  test "restores committed state and Bus subscriptions after controller shutdown" do
    start_supervised!(PersistentJido)
    id = unique_id("persistent-topology")

    instance =
      Builder.new(Swarm)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: id, input: %{worker_count: 2})

    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5_000)
    assert {:ok, _} = Cell.work(Controller.whereis_agent(controller, :workers, 1), 12)
    stop_supervised!({Controller, id})
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5_000)
    worker = Controller.whereis_agent(controller, :workers, 1)
    assert Server.agent(worker).state.total == 12

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :work), [Cell.work_signal!(5)])

    eventually(fn -> Server.agent(worker).state.total == 17 end)
    Process.exit(worker, :kill)

    eventually(
      fn ->
        current = Controller.whereis_agent(controller, :workers, 1)
        is_pid(current) and current != worker and Server.agent(current).state.total == 17
      end,
      timeout: 5_000
    )

    assert :ok = Controller.await_ready(controller, 5_000)
  end

  test "repairs a Bus and its subscriptions after a Bus failure", %{jido: jido} do
    instance =
      Builder.new(Swarm)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: "bus-repair", input: %{worker_count: 2})

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :work)
    Process.exit(bus, :kill)

    eventually(
      fn ->
        current = Controller.whereis_bus(controller, :work)
        is_pid(current) and current != bus and Controller.status(controller).status == :ready
      end,
      timeout: 5_000
    )

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :work), [Cell.work_signal!(5)])

    eventually(fn ->
      Server.agent(Controller.whereis_agent(controller, :workers, 1)).state.total == 5
    end)
  end

  test "a controller worker crash retains owned agents and their state", %{jido: jido} do
    instance = Independent.new!(id: "controller-repair")
    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    assert {:ok, _} = Cell.work(left, 9)

    {_, runtime, _, _} =
      Enum.find(
        Supervisor.which_children(controller),
        &(elem(&1, 0) == Jido.Topology.Controller.Runtime)
      )

    Process.exit(runtime, :kill)

    eventually(fn ->
      case Enum.find(
             Supervisor.which_children(controller),
             &(elem(&1, 0) == Jido.Topology.Controller.Runtime)
           ) do
        {_, pid, _, _} when is_pid(pid) -> pid != runtime
        _ -> false
      end
    end)

    assert :ok = Controller.await_ready(controller)
    assert Controller.whereis_agent(controller, :left) == left
    assert Server.agent(left).state.total == 9
  end
end
