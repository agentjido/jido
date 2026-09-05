defmodule Jido.Topology.CompositionRuntimeTest do
  use JidoTest.Case, async: false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, ComposedSystem}
  alias Jido.Signal.Bus
  alias Jido.Topology.{Builder, Controller, Ref}

  defmodule BlockReady do
    use Jido.Plugin

    def child_spec(_init) do
      %{id: __MODULE__, start: {Elixir.Agent, :start_link, [fn -> :ready end]}}
    end

    @impl true
    def await_ready(_runtime, _opts) do
      send(:persistent_term.get({__MODULE__, :observer}), {:readiness_blocked, self()})

      receive do
        :release -> :ok
      end
    end
  end

  defmodule SlowCell do
    use Jido.Agent, name: "composition_slow_cell"

    agent do
      plugin BlockReady
    end
  end

  defmodule PersistentJido do
    use Jido, otp_app: :jido, persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  test "status stays responsive and independent members start while readiness is blocked", %{
    jido: jido
  } do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Builder.new(name: "responsive")
      |> Builder.agent(:a_slow, SlowCell)
      |> Builder.agent(:z_fast, Cell)
      |> Builder.startup(concurrency: 2, task_timeout: 200, retry_interval: 10)
      |> Builder.build!(id: "responsive")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert_receive {:readiness_blocked, gate}, 1_000
    assert %{status: :starting, active: active} = Controller.status(controller, 100)
    assert active <= 2
    eventually(fn -> is_pid(Controller.whereis_agent(controller, :z_fast)) end)
    assert {:ok, _} = Cell.work(Controller.whereis_agent(controller, :z_fast), 3)

    eventually(
      fn ->
        Controller.status(controller, 100).errors["agent/a_slow"] == :startup_task_timeout
      end,
      timeout: 2_000
    )

    send(gate, :release)
    assert :ok = Controller.await_ready(controller, 2_000)
    assert Server.agent(Controller.whereis_agent(controller, :z_fast)).state.total == 3
  end

  test "global startup concurrency covers all included components", %{jido: jido} do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)
    child = Builder.new(name: "gated") |> Builder.agent(:cell, SlowCell) |> Builder.build!()

    instance =
      Builder.new(name: "bounded")
      |> Builder.include(:a, child)
      |> Builder.include(:b, child)
      |> Builder.include(:c, child)
      |> Builder.startup(concurrency: 1, task_timeout: 2_000)
      |> Builder.build!(id: "bounded")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert_receive {:readiness_blocked, first}, 1_000
    assert %{active: 1, pending: 2} = Controller.status(controller)
    refute_receive {:readiness_blocked, _}, 30
    send(first, :release)
    assert_receive {:readiness_blocked, second}, 1_000
    assert %{active: 1, pending: 1} = Controller.status(controller)
    send(second, :release)
    assert_receive {:readiness_blocked, third}, 1_000
    send(third, :release)
    assert :ok = Controller.await_ready(controller)
  end

  test "child activation keeps the parent PID from dispatch", %{jido: jido} do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Builder.new(name: "parent-snapshot")
      |> Builder.agent(:parent, Cell)
      |> Builder.agent(:child, SlowCell)
      |> Builder.owns(:parent, :child)
      |> Builder.startup(task_timeout: 5_000, retry_interval: 60_000)
      |> Builder.build!(id: "parent-snapshot")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert_receive {:readiness_blocked, gate}, 1_000
    parent = Controller.whereis_agent(controller, :parent)

    {_, runtime, _, _} =
      Enum.find(Supervisor.which_children(controller), &(elem(&1, 0) == Controller.Runtime))

    # Remove the live ready entry after dispatch. The task must keep its snapshot.
    :sys.replace_state(runtime, fn state -> %{state | ready: %{}} end)
    send(gate, :release)
    assert :ok = Controller.await_ready(controller)
    child = Controller.whereis_agent(controller, :child)
    assert Server.children(parent)["agent/child"].pid == child
  end

  test "a failed parent blocks child activation", %{jido: jido} do
    {:ok, unrelated} = Jido.start_agent(jido, Cell, id: "blocked-parent/agent/parent")

    instance =
      Builder.new(name: "blocked-parent")
      |> Builder.agent(:parent, Cell)
      |> Builder.agent(:child, Cell)
      |> Builder.owns(:parent, :child)
      |> Builder.startup(retry_interval: 60_000)
      |> Builder.build!(id: "blocked-parent")

    controller = start_supervised!({Controller, jido: jido, topology: instance})

    eventually(fn ->
      Controller.status(controller).errors == %{
        "agent/parent" => :agent_identity_in_use,
        "agent/child" => {:dependencies_unavailable, ["agent/parent"]}
      }
    end)

    assert Controller.whereis_agent(controller, :child) == nil
    assert Process.alive?(unrelated)
  end

  test "a team failure leaves the shared Bus and the other team running", %{jido: jido} do
    instance =
      Builder.new(ComposedSystem)
      |> Builder.startup(retry_interval: 10, concurrency: 4)
      |> Builder.build!(id: "team-repair")

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :events)
    west = Controller.whereis_agent(controller, Ref.ref(:west, :leader))
    east = Controller.whereis_agent(controller, Ref.ref(:east, :leader))
    :ok = Jido.stop_agent(jido, east)
    assert Process.alive?(bus)
    assert {:ok, _} = Cell.work(west, 7)

    eventually(
      fn ->
        replacement = Controller.whereis_agent(controller, Ref.ref(:east, :leader))

        is_pid(replacement) and replacement != east and
          map_size(Server.children(replacement)) == 2
      end,
      timeout: 5_000
    )

    assert Controller.whereis_bus(controller, :events) == bus
    assert Controller.whereis_agent(controller, Ref.ref(:west, :leader)) == west
    assert Server.agent(west).state.total == 7
  end

  test "saved component state and shared Bus subscriptions survive controller restart" do
    start_supervised!(PersistentJido)
    instance = ComposedSystem.new!(id: unique_id("composed-persistence"))
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    assert {:ok, _} =
             Cell.work(Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1), 10)

    stop_supervised!({Controller, instance.id})
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5_000)
    east = Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1)
    west = Controller.whereis_agent(controller, Ref.ref(:west, :workers), 1)
    assert Server.agent(east).state.total == 10
    assert Server.agent(west).state.total == 0

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :events), [Cell.work_signal!(2)])

    eventually(fn ->
      Server.agent(east).state.total == 12 and Server.agent(west).state.total == 2
    end)
  end
end
