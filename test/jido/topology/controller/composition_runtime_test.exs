defmodule Jido.Topology.Controller.CompositionRuntimeTest do
  use JidoTest.Case, async: false
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Cell, ComposedSystem}
  alias Jido.Signal.Bus
  alias Jido.Topology.{Controller, Ref}

  defmodule BlockReady do
    use Jido.Plugin

    @impl true
    defdelegate child_spec(init),
      to: Jido.Topology.Controller.CompositionRuntimeTest.BlockReady.Server

    @impl true
    defdelegate await_ready(runtime, opts),
      to: Jido.Topology.Controller.CompositionRuntimeTest.BlockReady.Server
  end

  defmodule BlockReady.Server do
    @behaviour Jido.Plugin

    @impl true
    def child_spec(_init) do
      %{id: BlockReady, start: {Elixir.Agent, :start_link, [fn -> :ready end]}}
    end

    @impl true
    def await_ready(_runtime, _opts) do
      observer = :persistent_term.get({BlockReady, :observer})
      test = if is_map(observer), do: observer.test, else: observer

      if is_map(observer) do
        Elixir.Agent.update(observer.counter, fn counts ->
          active = counts.active + 1
          %{active: active, max: max(counts.max, active)}
        end)
      end

      send(test, {:readiness_blocked, self()})

      receive do
        :release ->
          if is_map(observer) do
            Elixir.Agent.update(
              observer.counter,
              &Map.update!(&1, :active, fn active -> active - 1 end)
            )
          end

          :ok
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
    use Jido,
      otp_app: :jido,
      namespace: "composition-runtime-test",
      persistence: {Jido.Persistence.ETS, table: __MODULE__}
  end

  test "manual readiness observes an OTP replacement after a crash during startup", %{jido: jido} do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Jido.Topology.new!(%{
        name: "startup_restart",
        agents: [%{key: :slow, module: SlowCell}]
      })
      |> Jido.Topology.instantiate(id: unique_id("startup-restart"))
      |> Jido.Topology.unwrap!()

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert_receive {:readiness_blocked, _old_gate}, 1_000
    agents = Controller.name(jido, instance.id, :agents)
    [{"agent/slow", original, _, _}] = Supervisor.which_children(agents)
    ref = Process.monitor(original)
    Process.exit(original, :kill)
    assert_receive {:DOWN, ^ref, :process, ^original, :killed}, 1_000
    assert_receive {:readiness_blocked, gate}, 1_000
    eventually(fn -> Controller.status(controller).active == 0 end)
    send(gate, :release)
    [{"agent/slow", replacement, _, _}] = Supervisor.which_children(agents)
    assert replacement != original
    assert :ok = Server.await_ready(replacement)
    assert :ok = Controller.await_ready(controller, 1_000)
    assert Controller.whereis_agent(controller, :slow) == replacement
    assert Controller.status(controller).errors == %{}
  end

  test "coordinator replacement cancels old activation tasks and preserves members", %{jido: jido} do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Jido.Topology.new!(%{
        name: "activation_owner",
        agents: [%{key: :slow, module: SlowCell}, %{key: :fast, module: Cell}]
      })
      |> Jido.Topology.instantiate(id: unique_id("activation-owner"))
      |> Jido.Topology.unwrap!()

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert_receive {:readiness_blocked, gate}, 1_000
    eventually(fn -> is_pid(Controller.whereis_agent(controller, :fast)) end)
    fast = Controller.whereis_agent(controller, :fast)
    tasks = Controller.name(jido, instance.id, :tasks)
    eventually(fn -> length(Task.Supervisor.children(tasks)) == 1 end)
    [activation] = Task.Supervisor.children(tasks)
    activation_ref = Process.monitor(activation)

    {_, coordinator, _, _} =
      List.keyfind(Supervisor.which_children(controller), Controller.Runtime, 0)

    coordinator_ref = Process.monitor(coordinator)
    Process.exit(coordinator, :kill)
    assert_receive {:DOWN, ^coordinator_ref, :process, ^coordinator, :killed}, 1_000
    assert_receive {:DOWN, ^activation_ref, :process, ^activation, _}, 1_000
    send(gate, :release)
    assert :ok = Controller.await_ready(controller, 5_000)
    assert Controller.whereis_agent(controller, :fast) == fast
    assert is_pid(Controller.whereis_agent(controller, :slow))
    eventually(fn -> Task.Supervisor.children(tasks) == [] end)
  end

  test "status stays responsive and independent members start while readiness is blocked", %{
    jido: jido
  } do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 startup: [concurrency: 2, task_timeout: 200, retry_interval: 10],
                 name: "responsive",
                 agents: [%{key: :a_slow, module: SlowCell}, %{key: :z_fast, module: Cell}]
               }) do
          Jido.Topology.instantiate(definition, id: "responsive")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert_receive {:readiness_blocked, gate}, 1000
    assert %{status: :starting, active: active} = Controller.status(controller, 100)
    assert active <= 2
    eventually(fn -> is_pid(Controller.whereis_agent(controller, :z_fast)) end)

    {:ok, route_signal_1} = Cell.work_signal(%{value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(
               Controller.whereis_agent(controller, :z_fast),
               route_signal_1,
               []
             )

    eventually(
      fn ->
        Controller.status(controller, 100).errors["agent/a_slow"] == :startup_task_timeout
      end,
      timeout: 2000
    )

    send(gate, :release)
    assert :ok = Controller.await_ready(controller, 2000)
    assert Server.agent(Controller.whereis_agent(controller, :z_fast)).state.total == 3
  end

  test "global startup concurrency covers all included components", %{jido: jido} do
    counter = start_supervised!({Elixir.Agent, fn -> %{active: 0, max: 0} end})
    :persistent_term.put({BlockReady, :observer}, %{test: self(), counter: counter})
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)
    child = Jido.Topology.new!(%{name: "gated", agents: [%{key: :cell, module: SlowCell}]})

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 startup: [concurrency: 1, task_timeout: 2000],
                 name: "bounded",
                 includes: [
                   %{key: :a, topology: child},
                   %{key: :b, topology: child},
                   %{key: :c, topology: child}
                 ]
               }) do
          Jido.Topology.instantiate(definition, id: "bounded")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert_receive {:readiness_blocked, first}, 1_000
    assert %{active: 1, pending: 2} = Controller.status(controller)
    send(first, :release)
    assert_receive {:readiness_blocked, second}, 1_000
    assert %{active: 1, pending: 1} = Controller.status(controller)
    send(second, :release)
    assert_receive {:readiness_blocked, third}, 1_000
    send(third, :release)
    assert :ok = Controller.await_ready(controller)
    assert Elixir.Agent.get(counter, & &1) == %{active: 0, max: 1}
  end

  test "repair requests during startup preserve the shared concurrency limit", %{jido: jido} do
    counter = start_supervised!({Elixir.Agent, fn -> %{active: 0, max: 0} end})
    :persistent_term.put({BlockReady, :observer}, %{test: self(), counter: counter})
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 startup: [concurrency: 1, task_timeout: 2000],
                 name: "requested-repair",
                 agents: [%{key: :first, module: SlowCell}, %{key: :second, module: SlowCell}]
               }) do
          Jido.Topology.instantiate(definition, id: "requested-repair")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert_receive {:readiness_blocked, first}, 1_000

    assert {:error, %{message: "Topology update or placement requires an idle repair pass"}} =
             Controller.update(controller, instance)

    assert {:error, %{message: "Topology update or placement requires an idle repair pass"}} =
             Controller.place_agent(controller, :first, node())

    for _ <- 1..10, do: assert(:ok == Controller.reconcile(controller))
    assert %{active: 1, pending: 1} = Controller.status(controller)
    send(first, :release)
    assert_receive {:readiness_blocked, second}, 1_000
    assert %{active: 1, pending: 0} = Controller.status(controller)
    send(second, :release)
    assert :ok = Controller.await_ready(controller)
    assert %{status: :ready, active: 0, pending: 0, ready: 2} = Controller.status(controller)
    assert Jido.agent_count(jido) == 2
    assert Elixir.Agent.get(counter, & &1) == %{active: 0, max: 1}
  end

  test "child activation keeps the parent PID from dispatch", %{jido: jido} do
    :persistent_term.put({BlockReady, :observer}, self())
    on_exit(fn -> :persistent_term.erase({BlockReady, :observer}) end)

    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 startup: [task_timeout: 5000, retry_interval: 60000],
                 name: "parent-snapshot",
                 agents: [%{key: :parent, module: Cell}, %{key: :child, module: SlowCell}],
                 relationships: [%{parent: :parent, child: :child}]
               }) do
          Jido.Topology.instantiate(definition, id: "parent-snapshot")
        end
      )

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
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(%{
                 startup: [retry_interval: 60000],
                 name: "blocked-parent",
                 agents: [%{key: :parent, module: Cell}, %{key: :child, module: Cell}],
                 relationships: [%{parent: :parent, child: :child}]
               }) do
          Jido.Topology.instantiate(definition, id: "blocked-parent")
        end
      )

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

  test "a team stop leaves the shared Bus and the other team running", %{jido: jido} do
    instance =
      Jido.Topology.unwrap!(
        with {:ok, definition} <-
               Jido.Topology.new(
                 Map.put(ComposedSystem.topology(), :startup, retry_interval: 10, concurrency: 4)
               ) do
          Jido.Topology.instantiate(definition, id: "team-repair")
        end
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    bus = Controller.whereis_bus(controller, :events)
    west = Controller.whereis_agent(controller, Ref.ref(:west, :leader))
    east = Controller.whereis_agent(controller, Ref.ref(:east, :leader))
    :ok = Jido.stop_agent(jido, east)
    assert Process.alive?(bus)

    {:ok, route_signal_2} = Cell.work_signal(%{value: 7})

    assert {:ok, _} =
             Jido.AgentServer.call(west, route_signal_2, [])

    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)
    assert Controller.whereis_agent(controller, Ref.ref(:east, :leader)) == nil
    assert Controller.status(controller).status == :degraded

    assert Controller.whereis_bus(controller, :events) == bus
    assert Controller.whereis_agent(controller, Ref.ref(:west, :leader)) == west
    assert Server.agent(west).state.total == 7
  end

  test "saved component state and shared Bus subscriptions survive controller restart" do
    start_supervised!(PersistentJido)
    instance = ComposedSystem.new!(id: unique_id("composed-persistence"))
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    {:ok, route_signal_3} = Cell.work_signal(%{value: 10})

    assert {:ok, _} =
             Jido.AgentServer.call(
               Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1),
               route_signal_3,
               []
             )

    stop_supervised!({Controller, instance.id})
    controller = start_supervised!({Controller, jido: PersistentJido, topology: instance})
    assert :ok = Controller.await_ready(controller, 5000)
    east = Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1)
    west = Controller.whereis_agent(controller, Ref.ref(:west, :workers), 1)
    assert Server.agent(east).state.total == 10
    assert Server.agent(west).state.total == 0

    {:ok, command_signal_1} = Cell.work_signal(%{value: 2})

    assert {:ok, [_]} =
             Bus.publish(Controller.whereis_bus(controller, :events), [command_signal_1])

    eventually(fn ->
      Server.agent(east).state.total == 12 and Server.agent(west).state.total == 2
    end)
  end
end
