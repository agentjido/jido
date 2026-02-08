defmodule JidoTest.AgentServer.HierarchyTest do
  use JidoTest.Case, async: true

  @moduletag capture_log: true

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.ChildInfo
  alias Jido.AgentServer.{ParentRef, State}
  alias Jido.Signal

  # Actions for ParentAgent
  defmodule ChildExitAction do
    @moduledoc false
    use Jido.Action, name: "child_exit", schema: []

    def run(params, context) do
      events = Map.get(context.state, :child_events, [])
      {:ok, %{child_events: events ++ [params]}}
    end
  end

  defmodule SpawnChildAction do
    @moduledoc false
    use Jido.Action, name: "spawn_child", schema: []

    def run(%{module: mod, tag: tag}, _context) do
      {:ok, %{}, [%Directive.Spawn{child_spec: {mod, []}, tag: tag}]}
    end
  end

  defmodule SpawnAgentAction do
    @moduledoc false
    use Jido.Action, name: "spawn_agent", schema: []

    def run(%{module: mod, tag: tag} = params, _context) do
      opts = Map.get(params, :opts, %{})
      meta = Map.get(params, :meta, %{})
      {:ok, %{}, [Directive.spawn_agent(mod, tag, opts: opts, meta: meta)]}
    end
  end

  # Actions for ChildAgent
  defmodule OrphanedAction do
    @moduledoc false
    use Jido.Action, name: "orphaned", schema: []

    def run(params, context) do
      events = Map.get(context.state, :orphan_events, [])
      {:ok, %{orphan_events: events ++ [params]}}
    end
  end

  defmodule ParentAgent do
    @moduledoc false
    use Jido.Agent,
      name: "parent_agent",
      schema: [
        child_events: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"jido.agent.child.exit", ChildExitAction},
        {"child_exit", ChildExitAction},
        {"spawn_child", SpawnChildAction},
        {"spawn_agent", SpawnAgentAction}
      ]
    end
  end

  defmodule ChildAgent do
    @moduledoc false
    use Jido.Agent,
      name: "child_agent",
      schema: [
        orphan_events: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"jido.agent.orphaned", OrphanedAction},
        {"orphaned", OrphanedAction}
      ]
    end
  end

  describe "parent reference" do
    test "child can be started with parent reference", %{jido: jido} do
      {:ok, parent_pid} = AgentServer.start_link(agent: ParentAgent, id: "parent-1", jido: jido)

      parent_ref =
        ParentRef.new!(%{
          pid: parent_pid,
          id: "parent-1",
          tag: :worker,
          meta: %{role: "orchestrator"}
        })

      {:ok, child_pid} =
        AgentServer.start_link(
          agent: ChildAgent,
          id: "child-1",
          parent: parent_ref,
          jido: jido
        )

      {:ok, child_state} = AgentServer.state(child_pid)

      assert %ParentRef{} = child_state.parent
      assert child_state.parent.pid == parent_pid
      assert child_state.parent.id == "parent-1"
      assert child_state.parent.tag == :worker
      assert child_state.parent.meta == %{role: "orchestrator"}

      GenServer.stop(child_pid)
      GenServer.stop(parent_pid)
    end

    test "child with parent as map creates ParentRef", %{jido: jido} do
      {:ok, parent_pid} = AgentServer.start_link(agent: ParentAgent, id: "parent-2", jido: jido)

      {:ok, child_pid} =
        AgentServer.start_link(
          agent: ChildAgent,
          id: "child-2",
          parent: %{pid: parent_pid, id: "parent-2", tag: :helper},
          jido: jido
        )

      {:ok, child_state} = AgentServer.state(child_pid)

      assert %ParentRef{} = child_state.parent
      assert child_state.parent.tag == :helper

      GenServer.stop(child_pid)
      GenServer.stop(parent_pid)
    end

    test "child without parent has nil parent reference", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: ChildAgent, id: "orphan-1", jido: jido)
      {:ok, state} = AgentServer.state(pid)

      assert state.parent == nil

      GenServer.stop(pid)
    end
  end

  describe "on_parent_death: :stop (default)" do
    test "child stops when parent dies", %{jido: jido} do
      # Start parent under DynamicSupervisor to avoid linking to test process
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: "parent-stop-1", jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent-stop-1", tag: :worker})

      # Start child under DynamicSupervisor as well
      {:ok, child_pid} =
        AgentServer.start(
          agent: ChildAgent,
          id: "child-stop-1",
          parent: parent_ref,
          on_parent_death: :stop,
          jido: jido
        )

      child_ref = Process.monitor(child_pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)

      assert_receive {:DOWN, ^child_ref, :process, ^child_pid,
                      {:shutdown, {:parent_down, reason}}},
                     1000

      assert reason in [:shutdown, :noproc]
    end

    test "child stops with correct exit reason when parent dies", %{jido: jido} do
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: "parent-stop-log", jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent-stop-log", tag: :worker})

      {:ok, child_pid} =
        AgentServer.start(
          agent: ChildAgent,
          id: "child-stop-log",
          parent: parent_ref,
          on_parent_death: :stop,
          jido: jido
        )

      child_ref = Process.monitor(child_pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)

      assert_receive {:DOWN, ^child_ref, :process, ^child_pid,
                      {:shutdown, {:parent_down, reason}}},
                     1000

      assert reason in [:shutdown, :noproc]
    end
  end

  describe "on_parent_death: :continue" do
    test "child continues when parent dies", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: ParentAgent, id: "parent-continue-1", jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent-continue-1", tag: :worker})

      {:ok, child_pid} =
        AgentServer.start_link(
          agent: ChildAgent,
          id: "child-continue-1",
          parent: parent_ref,
          on_parent_death: :continue,
          jido: jido
        )

      GenServer.stop(parent_pid)

      eventually(fn -> not Process.alive?(parent_pid) end)

      # Child should still be alive and functional
      assert Process.alive?(child_pid)
      {:ok, child_state} = AgentServer.state(child_pid)
      assert child_state.parent.pid == parent_pid

      GenServer.stop(child_pid)
    end
  end

  describe "on_parent_death: :emit_orphan" do
    test "child emits orphan signal when parent dies", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: ParentAgent, id: "parent-orphan-1", jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent-orphan-1", tag: :worker})

      {:ok, child_pid} =
        AgentServer.start_link(
          agent: ChildAgent,
          id: "child-orphan-1",
          parent: parent_ref,
          on_parent_death: :emit_orphan,
          jido: jido
        )

      GenServer.stop(parent_pid)

      eventually_state(child_pid, fn state ->
        length(state.agent.state.orphan_events) == 1
      end)

      assert Process.alive?(child_pid)

      {:ok, child_state} = AgentServer.state(child_pid)

      [event] = child_state.agent.state.orphan_events
      assert event.parent_id == "parent-orphan-1"
      assert event.reason in [:normal, :noproc]

      GenServer.stop(child_pid)
    end
  end

  describe "child exit notification" do
    test "parent receives child exit signal when child is tracked", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: ParentAgent, id: "parent-track-1", jido: jido)

      child_pid =
        spawn(fn ->
          receive do
            :exit -> :ok
          end
        end)

      ref = Process.monitor(child_pid)

      child_info =
        ChildInfo.new!(%{
          pid: child_pid,
          ref: ref,
          module: ChildAgent,
          id: "tracked-child-1",
          tag: :worker
        })

      :sys.replace_state(parent_pid, fn state ->
        State.add_child(state, :worker, child_info)
      end)

      send(parent_pid, {:DOWN, ref, :process, child_pid, :test_exit})

      eventually_state(parent_pid, fn state ->
        length(state.agent.state.child_events) == 1
      end)

      {:ok, final_state} = AgentServer.state(parent_pid)

      [event] = final_state.agent.state.child_events
      assert event.tag == :worker
      assert event.reason == :test_exit

      send(child_pid, :exit)
      GenServer.stop(parent_pid)
    end

    test "child is removed from children map on exit", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: ParentAgent, id: "parent-remove-1", jido: jido)

      child_pid =
        spawn(fn ->
          receive do
            :exit -> :ok
          end
        end)

      ref = Process.monitor(child_pid)

      child_info =
        ChildInfo.new!(%{
          pid: child_pid,
          ref: ref,
          module: ChildAgent,
          id: "tracked-child-remove",
          tag: :temp_worker
        })

      :sys.replace_state(parent_pid, fn state ->
        State.add_child(state, :temp_worker, child_info)
      end)

      {:ok, state_with_child} = AgentServer.state(parent_pid)
      assert Map.has_key?(state_with_child.children, :temp_worker)

      send(parent_pid, {:DOWN, ref, :process, child_pid, :done})

      eventually_state(parent_pid, fn state ->
        not Map.has_key?(state.children, :temp_worker)
      end)

      {:ok, _state_without_child} = AgentServer.state(parent_pid)

      send(child_pid, :exit)
      GenServer.stop(parent_pid)
    end

    test "unknown DOWN message is ignored", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: ParentAgent, id: "ignore-down", jido: jido)

      random_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(random_pid) end)

      down_ref = make_ref()
      send(pid, {:DOWN, down_ref, :process, random_pid, :normal})

      eventually(fn ->
        {:messages, msgs} = Process.info(pid, :messages)
        not Enum.any?(msgs, fn msg -> match?({:DOWN, ^down_ref, _, _, _}, msg) end)
      end)

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "parent monitoring" do
    test "child monitors parent process", %{jido: jido} do
      parent_id = "parent-monitor-#{System.unique_integer([:positive])}"
      child_id = "child-monitor-#{System.unique_integer([:positive])}"

      # Start parent under DynamicSupervisor to avoid linking to test process
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: parent_id, tag: :worker})

      # Start child under DynamicSupervisor as well
      {:ok, child_pid} =
        AgentServer.start(
          agent: ChildAgent,
          id: child_id,
          parent: parent_ref,
          on_parent_death: :stop,
          jido: jido
        )

      # Wait for child to be fully initialized before killing parent
      {:ok, _state} = AgentServer.state(child_pid)
      {:ok, child_state} = AgentServer.state(child_pid)
      assert is_reference(Map.get(child_state, :parent_monitor_ref))

      child_ref = Process.monitor(child_pid)

      Process.exit(parent_pid, :kill)

      # Child should stop when parent dies - reason may be :killed or :noproc
      # depending on timing (whether parent is still dying or already dead)
      # :killed is not a benign reason, so it stays unwrapped as {:parent_down, :killed}
      # :noproc is benign, so it becomes {:shutdown, {:parent_down, :noproc}}
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, exit_reason}, 1000

      assert exit_reason in [
               {:parent_down, :killed},
               {:shutdown, {:parent_down, :noproc}}
             ]
    end
  end

  describe "SpawnAgent directive" do
    defp await_child(parent_pid, tag, timeout \\ 500) do
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
          Process.sleep(5)
          do_await_child(parent_pid, tag, deadline)

        {:error, _} ->
          flunk("Parent process died while waiting for child")
      end
    end

    test "spawns child agent with parent-child relationship", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal = Signal.new!("spawn_agent", %{module: ChildAgent, tag: :worker_1}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :worker_1)
      assert child_info.module == ChildAgent
      assert child_info.tag == :worker_1
      assert child_info.id == "#{parent_id}/worker_1"

      {:ok, child_state} = AgentServer.state(child_info.pid)
      assert %ParentRef{} = child_state.parent
      assert child_state.parent.pid == parent_pid
      assert child_state.parent.id == parent_id
      assert child_state.parent.tag == :worker_1

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "spawns child with custom ID from opts", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      custom_child_id = unique_id("my-custom-child")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal =
        Signal.new!(
          "spawn_agent",
          %{module: ChildAgent, tag: :custom, opts: %{id: custom_child_id}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :custom)
      assert child_info.id == custom_child_id

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "passes metadata to child via parent reference", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal =
        Signal.new!(
          "spawn_agent",
          %{module: ChildAgent, tag: :meta_child, meta: %{role: "processor", priority: 1}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :meta_child)

      {:ok, child_state} = AgentServer.state(child_info.pid)
      assert child_state.parent.meta == %{role: "processor", priority: 1}

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "spawns multiple children with different tags", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      for i <- 1..3 do
        signal =
          Signal.new!(
            "spawn_agent",
            %{module: ChildAgent, tag: :"worker_#{i}"},
            source: "/test"
          )

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
        DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      end

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "child exit notifies parent via ChildExit signal", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal =
        Signal.new!("spawn_agent", %{module: ChildAgent, tag: :dying_child}, source: "/test")

      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :dying_child)
      child_ref = Process.monitor(child_info.pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), child_info.pid)
      assert_receive {:DOWN, ^child_ref, :process, _, :shutdown}, 500

      eventually(fn ->
        case AgentServer.state(parent_pid) do
          {:ok, state} -> not Map.has_key?(state.children, :dying_child)
          _ -> false
        end
      end)

      {:ok, final_state} = AgentServer.state(parent_pid)
      refute Map.has_key?(final_state.children, :dying_child)
      assert length(final_state.agent.state.child_events) == 1

      [event] = final_state.agent.state.child_events
      assert event.tag == :dying_child
      assert event.reason == :shutdown

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "child inherits default on_parent_death: :stop", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal = Signal.new!("spawn_agent", %{module: ChildAgent, tag: :auto_stop}, source: "/test")
      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :auto_stop)
      child_ref = Process.monitor(child_info.pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)

      assert_receive {:DOWN, ^child_ref, :process, _, {:shutdown, {:parent_down, :shutdown}}},
                     1000
    end
  end
end
