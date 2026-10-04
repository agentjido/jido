defmodule Jido.Topology.RuntimeTest do
  use JidoTest.Case, async: true
  alias Jido.{AgentServer, Signal, Topology}
  alias Jido.Topology.{Controller, Runtime}
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule FailReady do
    use Jido.Plugin
    @impl true
    def child_spec(_init),
      do: %{id: __MODULE__, start: {Elixir.Agent, :start_link, [fn -> :ready end]}}

    @impl true
    def await_ready(_runtime, _opts), do: {:error, :injected_readiness_failure}
  end

  defmodule Headless do
    use Jido.Topology, name: "headless_runtime"

    topology do
      agents do
        agent :counter, CounterAgent
      end
    end
  end

  test "a lazy runtime adds and reports one neutral Agent definition", c do
    id = unique_id("dynamic_agent")
    topology = Topology.new!(name: "dynamic_agent")
    start_supervised!({Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy})

    definition = CounterAgent.definition()

    assert :ok =
             Runtime.add_agent(c.jido, id, "alice", definition, initial_state: %{count: 2})

    target = Runtime.target(c.jido, id)

    assert [%{key: "alice", definition: ^definition, initial_state: %{count: 2}}] =
             target.definition.agents

    assert %{active_members: 0, dormant_members: 1, target_revision: 1} =
             Runtime.status(c.jido, id)

    assert {:ok, %{state: %{count: 5}}} =
             Runtime.call(c.jido, id, "alice", add(3))

    assert %{active_members: 1, dormant_members: 0} = Runtime.status(c.jido, id)

    assert {:error, %Jido.Error.ValidationError{}} =
             Runtime.add_agent(c.jido, id, "alice", definition)
  end

  test "a headless DSL runtime starts only the requested dependency closure", c do
    target =
      Topology.new!(
        name: "closure",
        agents: [
          %{key: :first, module: CounterAgent},
          %{key: :last, module: CounterAgent, depends_on: [:first]},
          %{key: :idle, module: CounterAgent}
        ],
        groups: [%{key: :group, definition: CounterAgent.definition(), count: 2}]
      )

    id = unique_id("closure")
    start_supervised!({Runtime, jido: c.jido, id: id, topology: target, activation: :lazy})
    assert Runtime.director(c.jido, id) == nil
    assert :ok = Runtime.await_ready(c.jido, id)
    assert %{active_members: 0, dormant_members: 5} = Runtime.status(c.jido, id)

    assert {:ok, %{state: %{count: 2}}} =
             Runtime.call(c.jido, id, :last, add(2), %{timeout: 5_000})

    assert is_pid(Runtime.whereis_member(c.jido, id, :first))
    assert Runtime.whereis_member(c.jido, id, :idle) == nil
    assert {:ok, _} = Runtime.call(c.jido, id, {:group, :group, 1}, add(3))
    assert %{active_members: 3, dormant_members: 2} = Runtime.status(c.jido, id)
    assert {:error, :unknown_member} = Runtime.call(c.jido, id, :missing, add())
    assert {:error, :unknown_member} = Runtime.call(c.jido, id, {:group, :group, :missing}, add())
    assert {:error, :unknown_member} = Runtime.call(c.jido, id, {:group, :group, 0}, add())
    assert Runtime.whereis_child(c.jido, id, :missing) == nil
    assert Runtime.whereis_bus(c.jido, id, :missing) == nil
    assert {:error, :unknown_child} = Runtime.call(c.jido, id, {:child, :missing}, add())
  end

  test "the generated child does not create a director when no agent block exists", c do
    id = unique_id("headless")
    start_supervised!({Headless, jido: c.jido, id: id, activation: :deferred})
    assert Runtime.director(c.jido, id) == nil
    assert :ok = Runtime.activate(c.jido, id, :counter)
    assert :ok = Runtime.await_ready(c.jido, id)
    assert is_pid(Runtime.whereis_member(c.jido, id, :counter))
  end

  test "a waiting first call permits automatic repair after a start failure", c do
    id = unique_id("waiting_repair")

    target =
      Topology.new!(
        name: "waiting_repair",
        startup: %{retry_interval: 300},
        agents: [%{key: :counter, module: CounterAgent}]
      )

    {:ok, instance} = Topology.instantiate(target, id: id)
    member_id = instance.plan.agents["agent/counter"].id
    {:ok, foreign} = Jido.start_agent(c.jido, CounterAgent, id: member_id)
    start_supervised!({Runtime, jido: c.jido, id: id, topology: target, activation: :lazy})

    caller = Task.async(fn -> Runtime.call(c.jido, id, :counter, add(), timeout: 1_500) end)

    eventually(fn ->
      match?(
        %{errors: %{"agent/counter" => :agent_identity_in_use}},
        Runtime.status(c.jido, id)
      )
    end)

    monitor = Process.monitor(foreign)
    assert :ok = Jido.stop_agent(c.jido, foreign)
    assert_receive {:DOWN, ^monitor, :process, ^foreign, _}, 5_000

    assert {:ok, %{state: %{count: 1}}} = Task.await(caller, 5_000)
    assert %{active_members: 1, errors: %{}} = Runtime.status(c.jido, id)
  end

  test "readiness includes gateway and child status queries in its deadline", c do
    id = unique_id("readiness_deadline")

    target =
      Topology.new!(
        name: "readiness_deadline",
        children: [%{key: :team, topology: %{name: "leaf"}}]
      )

    start_supervised!({Runtime, jido: c.jido, id: id, topology: target, activation: :lazy})
    assert :ok = Runtime.await_ready(c.jido, id)

    for role <- [:gateway, {:gate, "team"}] do
      pid = GenServer.whereis(Controller.name(c.jido, id, role))
      assert :ok = :sys.suspend(pid)

      try do
        started = System.monotonic_time(:millisecond)
        assert {:error, :activation_timeout} = Runtime.await_ready(c.jido, id, 30)
        assert System.monotonic_time(:millisecond) - started < 500
      after
        :sys.resume(pid)
      end
    end
  end

  test "bad runtime options and unresolved child state fail before process startup", c do
    for extra <- [
          [activation: :bad],
          [repair: :bad],
          [max_restarts: -1],
          [max_depth: 33],
          [director: %{CounterAgent.definition() | schema: Zoi.object(%{required: Zoi.string()})}]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Runtime.start_link(
                 Keyword.merge([jido: c.jido, id: "invalid", topology: %{name: "invalid"}], extra)
               )
    end

    assert Jido.agent_count(c.jido) == 0

    assert {:error, %Jido.Error.ValidationError{}} =
             Runtime.call(c.jido, "missing", :member, :invalid)

    assert {:error, :topology_not_running} = Runtime.call(c.jido, "missing", :member, add())
    assert {:error, :topology_not_running} = Runtime.publish(c.jido, "missing", :bus, [])

    assert {:error, :activation_timeout} =
             Runtime.call(c.jido, "missing", :member, add(), timeout: 0)

    assert {:error, %Jido.Error.ValidationError{}} =
             Runtime.call(c.jido, "missing", :member, add(), timeout: -1)

    assert {:error, %Jido.Error.ValidationError{}} =
             Runtime.call(c.jido, "missing", :member, add(), typo: 1)
  end

  test "an eager child group is owned and an existing root cannot be adopted", c do
    leaf = %{name: "group_child", groups: [%{key: :group, module: CounterAgent, count: 1}]}

    target =
      Topology.new!(
        name: "parent",
        children: [
          %{
            key: :team,
            topology: leaf,
            activation: :eager,
            gate: %{commands: [%{type: "counter.add", member: {:group, :group, "1"}}]}
          }
        ]
      )

    id = unique_id("eager")
    pid = start_supervised!({Runtime, jido: c.jido, id: id, topology: target})
    assert :ok = Runtime.await_ready(c.jido, id)

    assert {:error, {:already_started, ^pid}} =
             Runtime.start_link(jido: c.jido, id: id, topology: target)

    assert {:ok, %{state: %{count: 1}}} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert :ok = Runtime.await_gate_idle(c.jido, id, :team)
    assert :ok = Supervisor.stop(pid)
    eventually(fn -> Jido.agent_count(c.jido) == 0 end)
  end

  test "a coordinator restart retains lazy selection and healthy member PIDs", c do
    id = unique_id("coordinator")
    start_supervised!({Headless, jido: c.jido, id: id, activation: :lazy})
    assert {:ok, _} = Runtime.call(c.jido, id, :counter, add(4))
    member = Runtime.whereis_member(c.jido, id, :counter)
    controller = Runtime.controller(c.jido, id)

    {Controller.Runtime, coordinator, _, _} =
      Enum.find(Supervisor.which_children(controller), &(elem(&1, 0) == Controller.Runtime))

    monitor = Process.monitor(coordinator)
    Process.exit(coordinator, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^coordinator, :killed}

    eventually(fn ->
      children = Supervisor.which_children(controller)

      Enum.any?(children, fn {key, pid, _, _} ->
        key == Controller.Runtime and is_pid(pid) and pid != coordinator
      end)
    end)

    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_member(c.jido, id, :counter) == member
    assert AgentServer.agent(member).state.count == 4
  end

  test "an unavailable target does not block healthy calls and degrades the parent gate", c do
    failing = %{CounterAgent.definition() | name: "failing_counter", plugins: [FailReady]}

    leaf = %{
      name: "leaf",
      startup: %{retry_interval: 10_000},
      agents: [%{key: :bad, definition: failing}, %{key: :good, module: CounterAgent}]
    }

    child = %{
      key: :team,
      topology: leaf,
      gate: %{commands: [%{type: "counter.add", member: :bad}]}
    }

    target = Topology.new!(name: "parent", children: [child])
    id = unique_id("scoped_failure")
    start_supervised!({Runtime, jido: c.jido, id: id, topology: target, activation: :lazy})

    assert {:error, :activation_timeout} =
             Runtime.call(c.jido, id, {:child, :team}, add(99), timeout: 30)

    child_id = id <> "/child/team"
    assert {:ok, %{state: %{count: 2}}} = Runtime.call(c.jido, child_id, :good, add(2))

    assert %{ready?: false, children: %{"team" => %{status: :degraded}}} =
             Runtime.status(c.jido, id)

    assert Runtime.whereis_member(c.jido, child_id, :bad) == nil
    assert is_pid(Runtime.whereis_member(c.jido, child_id, :good))
    assert {:error, :activation_timeout} = Runtime.await_ready(c.jido, id, 30)
  end

  test "a clean child stop stays failed and a later call cannot start it again", c do
    leaf = %{name: "leaf", agents: [%{key: :counter, module: CounterAgent}]}

    target =
      Topology.new!(
        name: "parent",
        children: [
          %{
            key: :team,
            topology: leaf,
            gate: %{commands: [%{type: "counter.add", member: :counter}]}
          }
        ]
      )

    id = unique_id("stopped_child")
    root = start_supervised!({Runtime, jido: c.jido, id: id, topology: target, activation: :lazy})
    assert {:ok, _} = Runtime.call(c.jido, id, {:child, :team}, add())
    child = Runtime.whereis_child(c.jido, id, :team)
    assert :ok = Supervisor.stop(child)

    eventually(fn ->
      match?(
        %{children: %{"team" => %{status: :failed, error: :child_stopped}}},
        Runtime.status(c.jido, id)
      )
    end)

    assert {:error, :child_stopped} = Runtime.call(c.jido, id, {:child, :team}, add())
    assert {:error, :child_stopped} = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_child(c.jido, id, :team) == nil
    assert Process.alive?(root)
  end

  defp add(count \\ 1),
    do: Signal.new!("counter.add", %{by: count, label: "runtime"}, source: "/test")
end
