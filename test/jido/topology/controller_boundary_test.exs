defmodule Jido.Topology.ControllerBoundaryTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.{Builder, Controller}

  @offline :"topology-unavailable@127.0.0.1"

  defmodule Observer do
    use Jido.Agent, name: "topology_boundary_observer"

    agent do
      schema Zoi.object(%{observer: Zoi.any()})
    end

    routes do
      route "jido.topology.lifecycle.**" do
        action _input, context: context do
          send(context.agent_state.observer, {:lifecycle, context.signal})
          {:ok, context.agent_state}
        end
      end
    end
  end

  test "invalid controller inputs fail before starting members", %{jido: jido} do
    instance = topology("invalid-controller")

    for opts <- [
          [],
          [jido: jido],
          [jido: nil, topology: instance],
          [jido: jido, topology: :invalid],
          [jido: jido, topology: %{instance | id: ""}],
          [jido: jido, topology: instance, unknown: true]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = Controller.start_link(opts)
      assert Jido.agent_count(jido) == 0
    end
  end

  test "local placement validates targets and options without replacing a live Agent", %{
    jido: jido
  } do
    instance =
      Builder.new(name: "local-placement")
      |> Builder.agent(:worker, Cell)
      |> Builder.group(:members, Cell, count: 1)
      |> Builder.build!(id: "local-placement")

    assert Controller.whereis(:not_a_running_jido, instance.id) == nil
    assert Controller.whereis(jido, instance.id) == nil
    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    assert Controller.whereis(jido, instance.id) == controller
    worker = Controller.whereis_agent(controller, :worker)
    member = Controller.whereis_agent(controller, :members, 1)
    assert {:ok, committed} = Cell.work(worker, 7)

    assert :ok = Controller.place_agent(controller, :worker, node())

    assert :ok =
             Controller.place_agent(controller, :members, node(), member: 1, timeout: :infinity)

    assert Controller.agent_node(controller, :worker) == node()
    assert Controller.agent_node(controller, :members, 1) == node()
    assert Controller.agent_node(controller, :missing) == nil
    assert Controller.whereis_bus(controller, :missing) == nil

    for target_node <- [nil, true, false, "not-an-atom", 123] do
      assert {:error, %{message: "Topology Agent node must be an atom"}} =
               Controller.place_agent(controller, :worker, target_node)
    end

    for opts <- [[timeout: 0], [timeout: -1], [timeout: :invalid], [unknown: true]] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Controller.place_agent(controller, :worker, node(), opts)
    end

    assert {:error, %{message: "Unknown topology Agent placement target"}} =
             Controller.place_agent(controller, :missing, node())

    assert Controller.whereis_agent(controller, :worker) == worker
    assert Controller.whereis_agent(controller, :members, 1) == member
    assert Server.agent(worker) == committed
  end

  test "failed remote placement retains its target and does not claim a successful move", %{
    jido: jido
  } do
    instance = topology("failed-placement")
    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :worker)
    monitor = Process.monitor(worker)

    assert :ok = Controller.place_agent(controller, :worker, @offline)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000

    eventually(fn -> Controller.status(controller).status == :degraded end)

    assert %{errors: %{"agent/worker" => {:placement_uncertain, @offline, _}}} =
             Controller.status(controller)

    assert Controller.agent_node(controller, :worker) == @offline
    assert Controller.whereis_agent(controller, :worker) == nil

    saved = %{definition: instance.definition, placements: %{"agent/worker" => @offline}}
    assert Jido.RuntimeStore.get(jido, :topology_placements, instance.id) == saved

    assert {:error, {:placement_uncertain, @offline, _}} =
             Controller.place_agent(controller, :worker, node())

    assert Jido.RuntimeStore.get(jido, :topology_placements, instance.id) == saved
    assert :ok = Supervisor.stop(controller)
    assert Jido.RuntimeStore.get(jido, :topology_placements, instance.id) == nil
  end

  test "saved placement survives a worker restart and drops keys outside the plan", %{jido: jido} do
    instance = topology("saved-placement", node: @offline)

    assert :ok =
             Jido.RuntimeStore.put(jido, :topology_placements, instance.id, %{
               definition: instance.definition,
               placements: %{"agent/worker" => node(), "agent/removed" => @offline}
             })

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :worker)
    assert {:ok, committed} = Cell.work(worker, 3)
    before = runtime(controller)
    monitor = Process.monitor(before)
    Process.exit(before, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^before, :killed}, 1_000

    eventually(fn -> is_pid(runtime(controller)) and runtime(controller) != before end)
    assert :ok = Controller.await_ready(controller)
    assert Controller.agent_node(controller, :worker) == node()
    assert Controller.whereis_agent(controller, :worker) == worker
    assert Server.agent(worker) == committed
    assert :sys.get_state(runtime(controller)).placements == %{"agent/worker" => node()}
  end

  test "placement cannot stop a foreign Agent or move a Bus subscriber off its node", %{
    jido: jido
  } do
    instance =
      Builder.new(name: "placement-ownership")
      |> Builder.agent(:worker, Cell)
      |> Builder.bus(:events)
      |> Builder.subscribe(:worker, to: :events, path: "examples.topology.cell.work")
      |> Builder.build!(id: "placement-ownership")

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :worker)

    assert {:error, %{message: "A remote topology Agent cannot subscribe to a local Bus"}} =
             Controller.place_agent(controller, :worker, @offline)

    assert Controller.whereis_agent(controller, :worker) == worker
    assert Process.alive?(worker)

    conflict = topology("foreign-placement")
    {:ok, foreign} = Jido.start_agent(jido, Cell, id: "foreign-placement/agent/worker")
    other = start_supervised!({Controller, jido: jido, topology: conflict, repair: :manual})
    eventually(fn -> Controller.status(other).status == :degraded end)

    assert {:error, %{message: "Topology Agent identity is in use"}} =
             Controller.place_agent(other, :worker, @offline)

    assert Process.alive?(foreign)
    assert Controller.whereis_agent(other, :worker) == nil
  end

  test "updates reject changed identity and resources before any live change", %{jido: jido} do
    instance = topology("update-boundaries")
    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    worker = Controller.whereis_agent(controller, :worker)
    before = Server.snapshot(worker)

    assert {:error, %{message: "Topology update identity does not match"}} =
             Controller.update(controller, topology("different"))

    target =
      Builder.new(instance.definition |> Map.from_struct())
      |> Builder.bus(:added)
      |> Builder.build!(id: instance.id)

    assert {:error, %{message: "Topology update cannot change resources"}} =
             Controller.update(controller, target)

    assert Controller.whereis_agent(controller, :worker) == worker
    assert Server.snapshot(worker) == before
    assert Controller.whereis_bus(controller, :added) == nil
  end

  test "lifecycle Signals reach a stable Ref and describe failed components", %{jido: _jido} do
    name = :"topology_lifecycle_#{System.unique_integer([:positive])}"
    observer_name = :"topology_observer_#{System.unique_integer([:positive])}"
    Process.register(self(), observer_name)
    namespace = unique_id("topology-lifecycle")
    start_supervised!({Jido, name: name, namespace: namespace}, id: name)

    {:ok, observer} =
      Jido.start_agent(name, Observer, id: "observer", initial_state: %{observer: observer_name})

    {:ok, ref} = Jido.agent_ref(name, "observer")
    instance = topology("lifecycle/failure")
    {:ok, foreign} = Jido.start_agent(name, Cell, id: instance.plan.agents["agent/worker"].id)

    controller =
      start_supervised!(
        {Controller, jido: name, topology: instance, lifecycle: ref, repair: :manual}
      )

    eventually(fn -> Controller.status(controller).status == :degraded end)

    assert_receive {:lifecycle,
                    %Jido.Signal{type: "jido.topology.lifecycle.component.failed"} = failed},
                   1_000

    assert failed.source == "/jido/topology/lifecycle%2Ffailure"
    assert failed.data.topology_id == instance.id
    assert failed.data.component == "agent/worker"
    assert failed.data.reason == "agent_identity_in_use"
    assert failed.data.kind == "agent"
    assert failed.data.node == Atom.to_string(node())

    assert_receive {:lifecycle,
                    %Jido.Signal{
                      type: "jido.topology.lifecycle.status.changed",
                      data: %{previous: nil, current: "degraded"}
                    }},
                   1_000

    assert :ok = Jido.stop_agent(name, foreign)
    assert :ok = Controller.reconcile(controller)
    assert :ok = Controller.await_ready(controller)

    assert_receive {:lifecycle,
                    %Jido.Signal{
                      type: "jido.topology.lifecycle.component.ready",
                      data: %{component: "agent/worker"}
                    }},
                   1_000

    assert_receive {:lifecycle,
                    %Jido.Signal{
                      type: "jido.topology.lifecycle.status.changed",
                      data: %{previous: "degraded", current: "ready"}
                    }},
                   1_000

    assert :ok = Supervisor.stop(controller)

    assert_receive {:lifecycle,
                    %Jido.Signal{
                      type: "jido.topology.lifecycle.operation.completed",
                      data: %{operation: "cleanup", status: "ok"}
                    }},
                   1_000

    assert Process.alive?(observer)
  end

  defp topology(id, opts \\ []) do
    Builder.new(name: "controller_boundaries")
    |> Builder.agent(:worker, Cell, opts)
    |> Builder.build!(id: id)
  end

  defp runtime(controller) do
    Enum.find_value(Supervisor.which_children(controller), fn
      {Controller.Runtime, pid, _, _} -> pid
      _ -> nil
    end)
  end
end
