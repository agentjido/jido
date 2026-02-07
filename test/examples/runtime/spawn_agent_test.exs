defmodule JidoExampleTest.SpawnAgentTest do
  @moduledoc """
  Example test demonstrating SpawnAgent directive and parent-child relationships.

  This test shows:
  - How to spawn child agents via Directive.spawn_agent/2
  - Parent receives "jido.agent.child.started" signal when child starts
  - Child can access parent info via state.__parent__
  - Using emit_to_parent/3 for child-to-parent communication
  - StopChild directive to gracefully stop tracked children
  - Parent tracks children in state.children map

  ## Key Patterns

  1. Use `Directive.spawn_agent(ChildModule, :tag)` to create a SpawnAgent directive
  2. Parent automatically receives `jido.agent.child.started` with child info
  3. Child state contains `__parent__` with ParentRef (pid, id, tag, meta)
  4. Use `Directive.emit_to_parent(agent, signal)` from child actions
  5. Use `Directive.stop_child(:tag)` to stop a tracked child

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 20_000

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.ParentRef
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Parent actions for spawning and managing children
  # ===========================================================================

  defmodule SpawnWorkerAction do
    @moduledoc false
    use Jido.Action,
      name: "spawn_worker",
      schema: [
        tag: [type: :atom, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(%{tag: tag} = params, _context) do
      meta = Map.get(params, :meta, %{})

      directive =
        Directive.spawn_agent(JidoExampleTest.SpawnAgentTest.WorkerAgent, tag, meta: meta)

      {:ok, %{last_spawned: tag}, [directive]}
    end
  end

  defmodule ChildStartedAction do
    @moduledoc false
    use Jido.Action,
      name: "child_started",
      schema: [
        pid: [type: :any, required: true],
        child_id: [type: :string, required: true],
        tag: [type: :atom, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(params, context) do
      started_events = Map.get(context.state, :child_started_events, [])

      event = %{
        pid: params.pid,
        child_id: params.child_id,
        tag: params.tag,
        meta: params.meta
      }

      {:ok, %{child_started_events: [event | started_events]}}
    end
  end

  defmodule WorkerResultAction do
    @moduledoc false
    use Jido.Action,
      name: "worker_result",
      schema: [
        result: [type: :any, required: true],
        from_tag: [type: :atom, required: true]
      ]

    def run(params, context) do
      results = Map.get(context.state, :worker_results, [])
      entry = %{result: params.result, from_tag: params.from_tag}
      {:ok, %{worker_results: [entry | results]}}
    end
  end

  defmodule StopWorkerAction do
    @moduledoc false
    use Jido.Action,
      name: "stop_worker",
      schema: [
        tag: [type: :atom, required: true],
        reason: [type: :atom, default: :normal]
      ]

    def run(%{tag: tag, reason: reason}, _context) do
      directive = Directive.stop_child(tag, reason: reason)
      {:ok, %{last_stopped: tag}, [directive]}
    end
  end

  # ===========================================================================
  # ACTIONS: Child actions for performing work
  # ===========================================================================

  defmodule DoWorkAction do
    @moduledoc false
    use Jido.Action,
      name: "do_work",
      schema: [
        task: [type: :string, required: true]
      ]

    def run(%{task: task}, context) do
      result = "Completed: #{task}"

      parent_ref = Map.get(context.state, :__parent__)
      from_tag = if parent_ref, do: parent_ref.tag, else: :unknown

      reply_signal =
        Signal.new!(
          "worker.result",
          %{result: result, from_tag: from_tag},
          source: "/worker"
        )

      emit_directive = Directive.emit_to_parent(%{state: context.state}, reply_signal)

      {:ok, %{last_task: task, status: :completed}, List.wrap(emit_directive)}
    end
  end

  # ===========================================================================
  # AGENTS: Parent and Child
  # ===========================================================================

  defmodule ParentAgent do
    @moduledoc false
    use Jido.Agent,
      name: "parent_agent",
      schema: [
        last_spawned: [type: :atom, default: nil],
        last_stopped: [type: :atom, default: nil],
        child_started_events: [type: {:list, :map}, default: []],
        worker_results: [type: {:list, :map}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"spawn_worker", SpawnWorkerAction},
        {"jido.agent.child.started", ChildStartedAction},
        {"worker.result", WorkerResultAction},
        {"stop_worker", StopWorkerAction}
      ]
    end
  end

  defmodule WorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "worker_agent",
      schema: [
        last_task: [type: :string, default: ""],
        status: [type: :atom, default: :idle]
      ]

    def signal_routes(_ctx) do
      [
        {"do_work", JidoExampleTest.SpawnAgentTest.DoWorkAction}
      ]
    end
  end

  # ===========================================================================
  # HELPERS
  # ===========================================================================

  defp await_child(parent_pid, tag, timeout \\ 1000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_child(parent_pid, tag, deadline)
  end

  defp do_await_child(parent_pid, tag, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      flunk("Timed out waiting for child #{inspect(tag)}")
    end

    case AgentServer.state(parent_pid) do
      {:ok, %{children: children}} when is_map_key(children, tag) ->
        children[tag]

      {:ok, _} ->
        Process.sleep(10)
        do_await_child(parent_pid, tag, deadline)

      {:error, _} ->
        flunk("Parent process died while waiting for child")
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "SpawnAgent directive creates children" do
    test "spawns child with parent-child relationship", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal = Signal.new!("spawn_worker", %{tag: :worker_1}, source: "/test")
      {:ok, agent} = AgentServer.call(parent_pid, signal)

      assert agent.state.last_spawned == :worker_1

      child_info = await_child(parent_pid, :worker_1)
      assert child_info.module == WorkerAgent
      assert child_info.tag == :worker_1
      assert child_info.id == "#{parent_id}/worker_1"

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "parent receives jido.agent.child.started signal", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal = Signal.new!("spawn_worker", %{tag: :notified_worker}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :notified_worker)

      eventually_state(parent_pid, fn state ->
        state.agent.state.child_started_events != []
      end)

      {:ok, state} = AgentServer.state(parent_pid)
      [event | _] = state.agent.state.child_started_events

      assert event.tag == :notified_worker
      assert event.pid == child_info.pid
      assert event.child_id == child_info.id

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "passes metadata to child via parent reference", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal =
        Signal.new!(
          "spawn_worker",
          %{tag: :meta_worker, meta: %{role: "processor", priority: 1}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :meta_worker)

      {:ok, child_state} = AgentServer.state(child_info.pid)
      assert child_state.agent.state.__parent__.meta == %{role: "processor", priority: 1}

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end

  describe "child can access parent info" do
    test "child state contains parent reference", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal = Signal.new!("spawn_worker", %{tag: :ref_worker}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :ref_worker)

      {:ok, child_state} = AgentServer.state(child_info.pid)
      parent_ref = child_state.agent.state.__parent__

      assert %ParentRef{} = parent_ref
      assert parent_ref.pid == parent_pid
      assert parent_ref.id == parent_id
      assert parent_ref.tag == :ref_worker

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end

  describe "emit_to_parent helper sends signals to parent" do
    test "child sends result to parent via emit_to_parent", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal = Signal.new!("spawn_worker", %{tag: :emitter_worker}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :emitter_worker)

      eventually(fn -> Process.alive?(child_info.pid) end, timeout: 1000)

      work_signal = Signal.new!("do_work", %{task: "process data"}, source: "/test")
      result = AgentServer.call(child_info.pid, work_signal)

      {:ok, child_agent} = result
      assert child_agent.state.status == :completed
      assert child_agent.state.last_task == "process data"

      eventually_state(parent_pid, fn state ->
        state.agent.state.worker_results != []
      end)

      {:ok, parent_state} = AgentServer.state(parent_pid)
      [result | _] = parent_state.agent.state.worker_results

      assert result.result == "Completed: process data"
      assert result.from_tag == :emitter_worker

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end

  describe "StopChild directive stops tracked children" do
    test "parent can stop child via StopChild directive", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      spawn_signal = Signal.new!("spawn_worker", %{tag: :stopable_worker}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, spawn_signal)

      child_info = await_child(parent_pid, :stopable_worker)
      child_ref = Process.monitor(child_info.pid)

      assert Process.alive?(child_info.pid)

      stop_signal = Signal.new!("stop_worker", %{tag: :stopable_worker}, source: "/test")
      {:ok, agent} = AgentServer.call(parent_pid, stop_signal)

      assert agent.state.last_stopped == :stopable_worker

      assert_receive {:DOWN, ^child_ref, :process, _, _}, 1000

      eventually_state(parent_pid, fn state ->
        not Map.has_key?(state.children, :stopable_worker)
      end)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end

  describe "parent tracks children in state.children map" do
    test "children map contains child info", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      for i <- 1..3 do
        signal = Signal.new!("spawn_worker", %{tag: :"worker_#{i}"}, source: "/test")
        {:ok, _agent} = AgentServer.call(parent_pid, signal)
      end

      _child1 = await_child(parent_pid, :worker_1)
      _child2 = await_child(parent_pid, :worker_2)
      _child3 = await_child(parent_pid, :worker_3)

      {:ok, parent_state} = AgentServer.state(parent_pid)

      assert Map.has_key?(parent_state.children, :worker_1)
      assert Map.has_key?(parent_state.children, :worker_2)
      assert Map.has_key?(parent_state.children, :worker_3)

      for tag <- [:worker_1, :worker_2, :worker_3] do
        child_info = parent_state.children[tag]
        assert child_info.module == WorkerAgent
        assert child_info.tag == tag
        assert is_pid(child_info.pid)
      end

      for tag <- [:worker_1, :worker_2, :worker_3] do
        child_info = parent_state.children[tag]
        DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      end

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "children map is updated when child exits", %{jido: jido} do
      parent_id = unique_id("parent")
      {:ok, parent_pid} = Jido.start_agent(jido, ParentAgent, id: parent_id)

      signal = Signal.new!("spawn_worker", %{tag: :exit_worker}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :exit_worker)

      {:ok, before_state} = AgentServer.state(parent_pid)
      assert Map.has_key?(before_state.children, :exit_worker)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)

      eventually_state(parent_pid, fn state ->
        not Map.has_key?(state.children, :exit_worker)
      end)

      {:ok, after_state} = AgentServer.state(parent_pid)
      refute Map.has_key?(after_state.children, :exit_worker)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end
end
