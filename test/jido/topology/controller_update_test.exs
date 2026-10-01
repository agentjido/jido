defmodule JidoTest.Topology.ControllerUpdateTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server

  alias Jido.Topology.Controller

  defmodule Worker do
    use Jido.Agent, name: "controller_update_worker"

    agent do
      schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
    end

    routes do
      route "worker.add" do
        action %{value: value},
          name: "controller_update_add",
          schema: Zoi.object(%{value: Zoi.integer()}),
          context: context do
          {:ok, %{context.agent_state | total: context.agent_state.total + value}}
        end
      end
    end
  end

  defmodule ReplacementWorker do
    use Jido.Agent, name: "controller_update_replacement_worker"

    agent do
      schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
    end
  end

  defmodule NumericWorker do
    use Jido.Agent, name: "controller_update_numeric_worker"

    agent do
      schema Zoi.object(%{value: Zoi.any() |> Zoi.default(0)})
    end
  end

  test "updates preserve the exact existing numeric state term", %{jido: jido} do
    initial = numeric_topology(unique_id("numeric-update"), 1)
    controller = start_supervised!({Controller, jido: jido, topology: initial, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    server = Controller.whereis_agent(controller, :value)
    before = Server.snapshot(server)

    assert :ok = Controller.update(controller, initial)
    assert :ok = Controller.await_ready(controller)
    changed = numeric_topology(initial.id, 1.0)
    assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, changed)
    assert Controller.whereis_agent(controller, :value) == server
    assert Server.snapshot(server) === before

    expanded = numeric_topology(initial.id, 1, true)
    assert :ok = Controller.update(controller, expanded)
    assert :ok = Controller.await_ready(controller)
    assert Controller.whereis_agent(controller, :value) == server
    assert is_pid(Controller.whereis_agent(controller, :added))
    assert Server.snapshot(server) === before
  end

  test "saved placements apply only to the exact original definition", %{jido: jido} do
    initial = numeric_topology(unique_id("numeric-placement"), 1)
    changed = numeric_topology(initial.id, 1.0)
    placements = %{"agent/value" => :"numeric-placement@127.0.0.1"}

    assert :ok =
             Jido.RuntimeStore.put(jido, :topology_placements, initial.id, %{
               definition: initial.definition,
               placements: placements
             })

    assert {:ok, ^initial, 0, ^placements, nil} =
             Jido.Topology.Controller.TargetStore.load(jido, initial)

    assert {:ok, ^changed, 0, %{}, nil} =
             Jido.Topology.Controller.TargetStore.load(jido, changed)
  end

  test "an additive update retains existing Agents and becomes the repair target", c do
    {:ok, initial} = topology(unique_id("update"), 2)

    controller =
      start_supervised!({Controller, jido: c.jido, topology: initial, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    original = workers(controller, 2)
    signal = Jido.Signal.new!("worker.add", %{value: 7}, source: "/test/topology-update")
    assert {:ok, %{state: %{total: 7}}} = Server.call(hd(original), signal)

    {:ok, target} = topology(initial.id, 4)
    assert :ok = Controller.update(controller, target)
    assert :ok = Controller.await_ready(controller)
    assert workers(controller, 2) == original
    assert Enum.all?(workers(controller, 4), &is_pid/1)
    assert Server.agent(hd(original)).state == %{total: 7}

    removed = Controller.whereis_agent(controller, :workers, 4)
    monitor = Process.monitor(removed)
    Process.exit(removed, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^removed, :killed}, 1_000
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_agent(controller, :workers, 4)
    assert is_pid(replacement)
    assert replacement != removed
  end

  test "a removal or changed existing definition has no live effect", c do
    {:ok, initial} = topology(unique_id("reject-update"), 2)
    controller = start_supervised!({Controller, jido: c.jido, topology: initial})
    assert :ok = Controller.await_ready(controller)
    original = workers(controller, 2)

    {:ok, smaller} = topology(initial.id, 1)
    assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, smaller)
    assert workers(controller, 2) == original

    {:ok, changed} = topology(initial.id, 2, ReplacementWorker)
    assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, changed)
    assert workers(controller, 2) == original
  end

  defp numeric_topology(id, value, add? \\ false) do
    agents = [%{key: :value, module: NumericWorker, initial_state: %{value: value}}]
    agents = if add?, do: agents ++ [%{key: :added, module: NumericWorker}], else: agents

    Jido.Topology.unwrap!(
      with {:ok, definition} <- Jido.Topology.new(name: "numeric-update", agents: agents) do
        Jido.Topology.instantiate(definition, id: id)
      end
    )
  end

  defp topology(id, count, module \\ Worker) do
    with {:ok, definition} <-
           Jido.Topology.new(%{
             startup: [retry_interval: 10],
             name: "controller_update_topology",
             groups: [%{key: :workers, module: module, count: count}]
           }) do
      Jido.Topology.instantiate(definition, id: id)
    end
  end

  defp workers(controller, count),
    do: Enum.map(1..count, &Controller.whereis_agent(controller, :workers, &1))
end
