defmodule JidoTest.Topology.ControllerUpdateTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Topology.Builder
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
    assert :ok = Jido.stop_agent(c.jido, removed)
    assert :ok = Controller.reconcile(controller)
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

  defp topology(id, count, module \\ Worker) do
    Builder.new(name: "controller_update_topology")
    |> Builder.group(:workers, module, count: count)
    |> Builder.startup(retry_interval: 10)
    |> Builder.build(id: id)
  end

  defp workers(controller, count),
    do: Enum.map(1..count, &Controller.whereis_agent(controller, :workers, &1))
end
