defmodule Jido.Topology.Controller.ResourceRaceTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Cell
  alias Jido.Signal.Bus
  alias Jido.Topology.{Controller, Resource}

  test "one manual repair accepts the Bus restarted by its resource supervisor", %{jido: jido} do
    instance =
      Jido.Topology.new!(%{
        name: "bus_restart_race",
        resources: [%{key: :events, kind: :bus}],
        agents: [%{key: :cell, module: Cell}],
        connections: [%{agent: :cell, to: :events, path: "examples.topology.cell.work"}]
      })
      |> Jido.Topology.instantiate(id: unique_id("bus-restart-race"))
      |> Jido.Topology.unwrap!()

    controller =
      start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})

    assert :ok = Controller.await_ready(controller)
    agent = Controller.whereis_agent(controller, :cell)
    {:ok, first} = Cell.work_signal(%{value: 7})
    assert {:ok, _} = Server.call(agent, first)
    bus = Controller.whereis_bus(controller, :events)
    pool = GenServer.whereis(Controller.name(jido, instance.id, :resources))
    tasks = GenServer.whereis(Controller.name(jido, instance.id, :tasks))

    {:via, Registry, {registry, _key}} =
      Bus.via_tuple(instance.plan.resources["bus/events"].id, jido: jido)

    {:links, links} = Process.info(bus, :links)

    {_, partition, _, _} =
      Enum.find(Supervisor.which_children(registry), fn {_, pid, _, _} -> pid in links end)

    with_suspended_pool(pool, tasks, fn ->
      :ok = :sys.suspend(partition)

      try do
        monitor = Process.monitor(bus)
        Process.exit(bus, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^bus, :killed}, 1_000
        # Keep the dead registration visible until the repair has requested a start.
        assert {:ok, ^bus} = Bus.whereis(instance.plan.resources["bus/events"].id, jido: jido)
        assert :ok = Controller.reconcile(controller)
        assert_start_queued(pool)
      after
        :ok = :sys.resume(partition)
      end
    end)

    assert :ok = Controller.await_ready(controller, 1_000)
    assert %{status: :ready, ready: 2, errors: errors} = Controller.status(controller)
    assert errors == %{}
    replacement = Controller.whereis_bus(controller, :events)
    assert replacement != bus
    assert Controller.whereis_agent(controller, :cell) == agent
    assert Server.agent(agent).state.total == 7
    {:ok, second} = Cell.work_signal(%{value: 5})
    assert {:ok, [_]} = Bus.publish(replacement, [second])
    eventually(fn -> Server.agent(agent).state.total == 12 end)
  end

  test "a Bus started elsewhere during resource creation is not adopted", %{jido: jido} do
    pool = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    spec = %{kind: :bus, key: "bus/events", id: unique_id("foreign-bus"), config: []}
    context = %{jido: jido, pool: pool}

    task =
      Task.async(fn ->
        receive do
          :start -> Resource.ensure(spec, context)
        end
      end)

    foreign =
      with_suspended_pool(pool, task.pid, fn ->
        send(task.pid, :start)
        assert_start_queued(pool)
        start_supervised!({Bus, name: spec.id, jido: jido})
      end)

    assert {:error, :bus_identity_in_use} = Task.await(task)
    assert DynamicSupervisor.which_children(pool) == []
    assert Resource.whereis(spec, context) == nil
    assert :ok = Supervisor.stop(pool)
    assert {:ok, ^foreign} = Bus.whereis(spec.id, jido: jido)
  end

  defp with_suspended_pool(pool, traced, fun) do
    :erlang.trace(traced, true, [:send, :set_on_spawn, {:tracer, self()}])
    :ok = :sys.suspend(pool)

    try do
      fun.()
    after
      :erlang.trace(traced, false, [:all])
      :ok = :sys.resume(pool)
    end
  end

  defp assert_start_queued(pool) do
    assert_receive {:trace, _task, :send, {:"$gen_call", _, {:start_child, _}}, ^pool}, 1_000
  end
end
