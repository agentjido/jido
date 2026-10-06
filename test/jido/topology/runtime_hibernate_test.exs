defmodule Jido.Topology.RuntimeHibernateTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal, Topology}
  alias Jido.Topology.{Controller, Runtime}
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule FailingAdapter do
    @behaviour Jido.Persistence.Adapter

    def validate_options(opts), do: Jido.Persistence.ETS.validate_options(opts)

    def get(key, opts), do: Jido.Persistence.ETS.get(key, opts)

    def put(key, value, opts) do
      case Elixir.Agent.get(Keyword.fetch!(opts, :control), & &1) do
        :ok -> Jido.Persistence.ETS.put(key, value, opts)
        {:error, reason} -> {:error, reason}
      end
    end

    def compare_and_swap(key, expected, value, opts) do
      case Elixir.Agent.get(Keyword.fetch!(opts, :control), & &1) do
        :ok -> Jido.Persistence.ETS.compare_and_swap(key, expected, value, opts)
        {:error, reason} -> {:error, reason}
      end
    end

    defdelegate delete(key, opts), to: Jido.Persistence.ETS
  end

  defmodule ControlledReady do
    use Jido.Plugin

    @impl true
    def child_spec(opts),
      do: %{id: __MODULE__, start: {Elixir.Agent, :start_link, [fn -> opts end]}}

    @impl true
    def await_ready(_runtime, opts) do
      case :persistent_term.get(Keyword.fetch!(opts, :gate), :ok) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, reason}

        {:block, test_pid, token} ->
          send(test_pid, {:readiness_blocked, token, self()})

          receive do
            {:release_readiness, ^token} -> :ok
          end
      end
    end
  end

  defmodule BlockingAgent do
    use Jido.Agent, name: "topology_hibernate_blocking_agent"

    agent do
      schema Zoi.object(%{
               count: Zoi.integer() |> Zoi.default(0),
               history: Zoi.list(Zoi.string()) |> Zoi.default([])
             })
    end

    routes do
      route "counter.block", JidoTest.AgentFixtures.BlockingAdd
    end
  end

  test "running Hibernate checkpoints, stays asleep through repair, and a call thaws it", c do
    id = unique_id("hibernate-running")
    start_runtime(c.jido, id, :lazy)

    assert {:ok, %{state: %{count: 4}}} = Runtime.call(c.jido, id, :counter, add(4))
    original = Runtime.whereis_member(c.jido, id, :counter)
    monitor = Process.monitor(original)

    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    assert_receive {:DOWN, ^monitor, :process, ^original, {:shutdown, :hibernate}}, 1_000
    assert Runtime.whereis_member(c.jido, id, :counter) == nil

    assert %{
             active_members: 0,
             dormant_members: 0,
             hibernated_members: 1,
             member_statuses: %{"agent/counter" => :hibernated}
           } = Runtime.status(c.jido, id)

    assert :ok = Controller.reconcile(Runtime.controller(c.jido, id))
    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_member(c.jido, id, :counter) == nil

    assert {:ok, %{state: %{count: 5}}} = Runtime.call(c.jido, id, :counter, add())
    restored = Runtime.whereis_member(c.jido, id, :counter)
    assert is_pid(restored)
    assert restored != original
    assert AgentServer.agent(restored).state.count == 5
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :ready

    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    assert :ok = Runtime.thaw(c.jido, id, :counter)
    assert :ok = Runtime.thaw(c.jido, id, :counter)
    assert AgentServer.agent(Runtime.whereis_member(c.jido, id, :counter)).state.count == 5
  end

  test "dormant Hibernate does not start a process and explicit Thaw starts it", c do
    id = unique_id("hibernate-dormant")
    start_runtime(c.jido, id, :lazy)

    assert Runtime.whereis_member(c.jido, id, :counter) == nil
    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    assert Runtime.whereis_member(c.jido, id, :counter) == nil
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :hibernated

    assert :ok = Runtime.thaw(c.jido, id, :counter)
    assert is_pid(Runtime.whereis_member(c.jido, id, :counter))
    assert :ok = Runtime.thaw(c.jido, id, :counter)
  end

  test "Hibernate rejects sorted transitive selected dependents", c do
    id = unique_id("hibernate-dependents")

    topology =
      Topology.new!(
        name: "hibernate_dependents",
        agents: [
          %{key: :root, module: CounterAgent},
          %{key: :charlie, module: CounterAgent, depends_on: [:bravo]},
          %{key: :bravo, module: CounterAgent, depends_on: [:root]},
          %{key: :delta, module: CounterAgent, depends_on: [:root]}
        ]
      )

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy, repair: :manual}
    )

    assert :ok = Runtime.activate(c.jido, id, :charlie)
    assert :ok = Runtime.activate(c.jido, id, :delta)
    assert :ok = Runtime.await_ready(c.jido, id)

    assert {:error, {:hibernate_blocked, ["agent/bravo", "agent/charlie", "agent/delta"]}} =
             Runtime.hibernate(c.jido, id, :root)

    assert is_pid(Runtime.whereis_member(c.jido, id, :root))
  end

  test "eager target changes do not wake a hibernated member and removal clears its marker", c do
    id = unique_id("hibernate-eager")
    topology = Topology.new!(name: "hibernate_eager")

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :eager, repair: :manual}
    )

    assert :ok = Runtime.add_agent(c.jido, id, :alice, CounterAgent.definition())
    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = Runtime.hibernate(c.jido, id, :alice)

    assert :ok = Runtime.add_agent(c.jido, id, :bob, CounterAgent.definition())
    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.whereis_member(c.jido, id, :alice) == nil
    assert is_pid(Runtime.whereis_member(c.jido, id, :bob))
    assert Runtime.status(c.jido, id).member_statuses["agent/alice"] == :hibernated

    assert :ok = Runtime.remove_agent(c.jido, id, :alice)
    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = Runtime.add_agent(c.jido, id, :alice, CounterAgent.definition())
    assert :ok = Runtime.await_ready(c.jido, id)
    assert Runtime.status(c.jido, id).member_statuses["agent/alice"] == :ready
  end

  test "a Controller runtime restart loses the volatile marker", c do
    id = unique_id("hibernate-restart")
    start_runtime(c.jido, id, :eager)
    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = Runtime.hibernate(c.jido, id, :counter)

    controller = Runtime.controller(c.jido, id)
    old_runtime = controller_runtime(controller)
    Process.exit(old_runtime, :kill)

    eventually(fn ->
      current = controller_runtime(controller)
      is_pid(current) and current != old_runtime
    end)

    assert :ok = Runtime.await_ready(c.jido, id)
    assert is_pid(Runtime.whereis_member(c.jido, id, :counter))
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :ready
  end

  test "a persistence failure keeps the member available", _c do
    control = start_supervised!({Elixir.Agent, fn -> :ok end})
    jido = String.to_atom(unique_id("hibernate-storage"))

    start_supervised!(
      {Jido,
       name: jido,
       namespace: "hibernate/#{jido}",
       persistence: {FailingAdapter, table: jido, control: control}},
      id: jido
    )

    id = unique_id("hibernate-storage")
    start_runtime(jido, id, :eager)
    assert :ok = Runtime.await_ready(jido, id)
    assert {:ok, %{state: %{count: 3}}} = Runtime.call(jido, id, :counter, add(3))
    pid = Runtime.whereis_member(jido, id, :counter)
    Elixir.Agent.update(control, fn _ -> {:error, :storage_unavailable} end)

    assert {:error, {:indeterminate, :storage_unavailable}} =
             Runtime.hibernate(jido, id, :counter)

    assert %{phase: :idle} = AgentServer.status(pid)
    assert Runtime.whereis_member(jido, id, :counter) == pid
    assert Runtime.status(jido, id).member_statuses["agent/counter"] == :ready

    Elixir.Agent.update(control, fn _ -> :ok end)
    assert :ok = Runtime.hibernate(jido, id, :counter)
    assert :ok = Runtime.thaw(jido, id, :counter)
    restored = Runtime.whereis_member(jido, id, :counter)
    assert AgentServer.agent(restored).state.count == 3
  end

  test "a definite Thaw failure retains hibernation and its error", c do
    gate = String.to_atom(unique_id("controlled-ready"))
    on_exit(fn -> :persistent_term.erase(gate) end)

    definition = %{
      CounterAgent.definition()
      | plugins: [{ControlledReady, gate: gate}]
    }

    id = unique_id("hibernate-thaw-failure")

    topology =
      Topology.new!(
        name: "hibernate_thaw_failure",
        startup: %{task_timeout: 1_000},
        agents: [%{key: :counter, definition: definition}]
      )

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :eager, repair: :manual}
    )

    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    :persistent_term.put(gate, {:error, :injected_readiness_failure})

    assert {:error, {:thaw_failed, "agent/counter", {:member_start_failed, readiness_error}}} =
             Runtime.thaw(c.jido, id, :counter)

    assert inspect(readiness_error) =~ "injected_readiness_failure"

    assert Runtime.whereis_member(c.jido, id, :counter) == nil

    assert %{
             member_statuses: %{"agent/counter" => :hibernated},
             errors: %{"agent/counter" => {:member_start_failed, ^readiness_error}}
           } = Runtime.status(c.jido, id)

    assert {:error, {:thaw_failed, "agent/counter", {:member_start_failed, call_readiness_error}}} =
             Runtime.call(c.jido, id, :counter, add(9))

    assert inspect(call_readiness_error) =~ "injected_readiness_failure"
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :hibernated

    :persistent_term.put(gate, :ok)
    assert :ok = Runtime.thaw(c.jido, id, :counter)
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :ready
    assert AgentServer.agent(Runtime.whereis_member(c.jido, id, :counter)).state.count == 0
  end

  test "an indeterminate Thaw timeout reports unavailable until readiness resolves", c do
    gate = String.to_atom(unique_id("controlled-timeout"))
    token = make_ref()
    on_exit(fn -> :persistent_term.erase(gate) end)

    definition = %{
      CounterAgent.definition()
      | plugins: [{ControlledReady, gate: gate}]
    }

    id = unique_id("hibernate-thaw-timeout")

    topology =
      Topology.new!(
        name: "hibernate_thaw_timeout",
        startup: %{task_timeout: 1_000},
        agents: [%{key: :counter, definition: definition}]
      )

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :eager, repair: :manual}
    )

    assert :ok = Runtime.await_ready(c.jido, id)
    assert :ok = Runtime.hibernate(c.jido, id, :counter)
    :persistent_term.put(gate, {:block, self(), token})

    assert {:error, {:indeterminate, :activation_timeout}} =
             Runtime.thaw(c.jido, id, :counter, timeout: 10)

    assert_receive {:readiness_blocked, ^token, readiness}
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :unavailable
    send(readiness, {:release_readiness, token})

    eventually(fn ->
      Runtime.status(c.jido, id).member_statuses["agent/counter"] == :ready
    end)

    assert is_pid(Runtime.whereis_member(c.jido, id, :counter))
  end

  test "Hibernate waits for a Gateway-admitted call before it checkpoints", c do
    id = unique_id("hibernate-admitted-call")

    topology =
      Topology.new!(
        name: "hibernate_admitted_call",
        agents: [%{key: :counter, module: BlockingAgent}]
      )

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy, repair: :manual}
    )

    gate = make_ref()

    signal =
      Signal.new!(
        "counter.block",
        %{by: 2, label: "held", test_pid: self(), gate: gate},
        source: "/test"
      )

    caller = Task.async(fn -> Runtime.call(c.jido, id, :counter, signal) end)
    assert_receive {:agent_action_blocked, ^gate, worker}
    original = Runtime.whereis_member(c.jido, id, :counter)
    monitor = Process.monitor(original)
    hibernate = Task.async(fn -> Runtime.hibernate(c.jido, id, :counter) end)
    runtime = c.jido |> Runtime.controller(id) |> controller_runtime()

    eventually(fn -> :sys.get_state(runtime).hibernate_waiters != [] end)
    send(worker, {:release, gate})

    assert {:ok, %{state: %{count: 2}}} = Task.await(caller)
    assert :ok = Task.await(hibernate)
    assert_receive {:DOWN, ^monitor, :process, ^original, {:shutdown, :hibernate}}
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :hibernated
  end

  test "a Hibernate deadline during admitted work is indeterminate and does not stop later", c do
    id = unique_id("hibernate-admitted-timeout")

    topology =
      Topology.new!(
        name: "hibernate_admitted_timeout",
        agents: [%{key: :counter, module: BlockingAgent}]
      )

    start_supervised!(
      {Runtime, jido: c.jido, id: id, topology: topology, activation: :lazy, repair: :manual}
    )

    gate = make_ref()

    signal =
      Signal.new!(
        "counter.block",
        %{by: 1, label: "held", test_pid: self(), gate: gate},
        source: "/test"
      )

    caller = Task.async(fn -> Runtime.call(c.jido, id, :counter, signal) end)
    assert_receive {:agent_action_blocked, ^gate, worker}
    original = Runtime.whereis_member(c.jido, id, :counter)
    hibernate = Task.async(fn -> Runtime.hibernate(c.jido, id, :counter, timeout: 10) end)
    runtime = c.jido |> Runtime.controller(id) |> controller_runtime()

    eventually(fn -> :sys.get_state(runtime).hibernate_waiters != [] end)
    assert {:error, {:indeterminate, :hibernate_timeout}} = Task.await(hibernate)
    send(worker, {:release, gate})
    assert {:ok, %{state: %{count: 1}}} = Task.await(caller)
    eventually(fn -> :sys.get_state(runtime).hibernate_waiters == [] end)

    assert Runtime.whereis_member(c.jido, id, :counter) == original
    assert Runtime.status(c.jido, id).member_statuses["agent/counter"] == :ready
  end

  defp start_runtime(jido, id, activation) do
    topology =
      Topology.new!(
        name: "hibernate_counter",
        agents: [%{key: :counter, module: CounterAgent}]
      )

    start_supervised!(
      {Runtime, jido: jido, id: id, topology: topology, activation: activation, repair: :manual}
    )
  end

  defp controller_runtime(controller) do
    Enum.find_value(Supervisor.which_children(controller), fn
      {Controller.Runtime, pid, _, _} -> pid
      _other -> nil
    end)
  end

  defp add(count \\ 1),
    do: Signal.new!("counter.add", %{by: count, label: "hibernate"}, source: "/test")
end
