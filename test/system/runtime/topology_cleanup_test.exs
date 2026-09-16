Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.TopologyCleanup do
  use JidoTest.System.Case, async: false
  @moduletag :system
  @moduletag adapter: :ets
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Cell
  alias Jido.Signal.Bus
  alias Jido.Topology.{Builder, Controller}
  alias JidoTest.System.Observability

  @tag :research
  test "a partial accepted update accounts for members when its control tree dies during cleanup",
       c do
    build = fn count ->
      Builder.new(name: "partial_cleanup")
      |> Builder.group(:workers, Cell, count: count)
      |> Builder.bus(:events)
      |> Builder.build!(id: c.namespace)
    end

    initial = build.(1)

    controller =
      start_supervised!(
        Supervisor.child_spec({Controller, jido: c.jido, topology: initial, repair: :manual},
          restart: :temporary
        )
      )

    assert :ok = Controller.await_ready(controller)
    old_bus = Controller.whereis_bus(controller, :events)
    pool = Controller.name(c.jido, c.namespace, :resources)
    assert :ok = DynamicSupervisor.terminate_child(pool, old_bus)

    # A different owner takes the exact resource identity. This is a real
    # startup conflict; the Controller must not adopt or remove that Bus.
    bus_id = initial.plan.resources["bus/events"].id
    unrelated = start_supervised!({Bus, name: bus_id, jido: c.jido}, id: :unrelated_bus)
    assert :ok = Controller.update(controller, build.(3))

    Observability.await(c.observer, fn
      {_, [:jido, :topology, :operation, :stop], _, %{topology_operation: :update}} -> true
      _ -> false
    end)

    assert %{agents: 3, active: 0, pending: 0, errors: errors} = Controller.status(controller)
    assert errors["bus/events"] == :bus_identity_in_use
    assert Controller.whereis_bus(controller, :events) == nil
    owned = for member <- 1..3, do: Controller.whereis_agent(controller, :workers, member)
    assert Enum.all?(owned, &is_pid/1)

    for {pid, value} <- Enum.with_index(owned, 1) do
      assert {:ok, _} = Cell.work(pid, value)
      snapshot = Server.snapshot(pid)
      assert {:ok, saved, 1} = load(c, snapshot.agent.id, Cell)
      assert saved == snapshot.agent
    end

    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :topology, :operation, :start],
        &__MODULE__.gate/4,
        {self(), c.namespace}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    stop =
      Task.async(fn ->
        try do
          Supervisor.stop(controller, :normal, 10_000)
        catch
          :exit, reason -> {:exit, reason}
        end
      end)

    assert_receive {:cleanup_held, runtime}, 10_000
    monitors = for pid <- [controller, runtime], do: {pid, Process.monitor(pid)}
    Observability.killed(c.observer, runtime)
    Process.exit(runtime, :kill)
    Process.exit(controller, :kill)
    await_down(monitors)
    Task.await(stop, 10_000)

    {_, [:jido, :topology, :ownership, :settled], measurements, metadata} =
      Observability.await(c.observer, fn
        {_, [:jido, :topology, :ownership, :settled], _, %{topology_id: id}} ->
          id == c.namespace

        _ ->
          false
      end)

    assert metadata.status == :ok
    assert measurements.failed_count == 0

    assert Enum.any?(Jido.Telemetry.metrics(), fn metric ->
             metric.name == [:jido, :topology, :ownership, :settled, :count] and
               metric.event_name == [:jido, :topology, :ownership, :settled] and
               metric.tags == [:status]
           end)

    assert Process.alive?(unrelated)
    survivors = Enum.filter(owned, &Process.alive?/1)
    for pid <- survivors, do: stop_agent(c, pid)
    assert_empty_agent_pool(c)
    assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

    assert survivors == [],
           "SYSTEM-TOPOLOGY-03: #{length(survivors)} owned members survived control-tree failure during cleanup. The test removed them; Controller shutdown did not."
  end

  def gate(_event, _measurements, %{topology_operation: :cleanup, topology_id: id}, {owner, id}) do
    monitor = Process.monitor(owner)
    send(owner, {:cleanup_held, self()})
    receive do: ({:DOWN, ^monitor, :process, ^owner, _} -> :ok)
  end

  def gate(_event, _measurements, _metadata, _config), do: :ok
end
