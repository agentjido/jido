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
      restart = Map.get(params, :restart, :transient)
      {:ok, %{}, [Directive.spawn_agent(mod, tag, opts: opts, meta: meta, restart: restart)]}
    end
  end

  defmodule AdoptChildAction do
    @moduledoc false
    use Jido.Action, name: "adopt_child", schema: []

    def run(%{child: child, tag: tag} = params, _context) do
      meta = Map.get(params, :meta, %{})
      {:ok, %{}, [Directive.adopt_child(child, tag, meta: meta)]}
    end
  end

  # Actions for ChildAgent
  defmodule OrphanedAction do
    @moduledoc false
    use Jido.Action, name: "orphaned", schema: []

    def run(params, context) do
      events = Map.get(context.state, :orphan_events, [])

      event =
        params
        |> Map.put(:parent_available, not is_nil(Map.get(context.state, :__parent__)))
        |> Map.put(
          :orphaned_from_id,
          context.state
          |> Map.get(:__orphaned_from__)
          |> case do
            %ParentRef{id: id} -> id
            _ -> nil
          end
        )
        |> Map.put(
          :can_emit_to_parent,
          not is_nil(Directive.emit_to_parent(%{state: context.state}, %{type: "orphan.check"}))
        )

      {:ok, %{orphan_events: events ++ [event]}}
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
        {"spawn_agent", SpawnAgentAction},
        {"adopt_child", AdoptChildAction}
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

    test "child exits with {:shutdown, _} even when parent crashes abnormally", %{jido: jido} do
      {:ok, parent_pid} =
        AgentServer.start_link(agent: ParentAgent, id: "parent-crash-1", jido: jido)

      parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent-crash-1", tag: :worker})

      {:ok, child_pid} =
        AgentServer.start_link(
          agent: ChildAgent,
          id: "child-crash-1",
          parent: parent_ref,
          on_parent_death: :stop,
          jido: jido
        )

      assert Process.alive?(child_pid)
      child_ref = Process.monitor(child_pid)

      Process.flag(:trap_exit, true)
      Process.exit(parent_pid, {:function_clause, :simulated_crash})

      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, exit_reason}, 5000
      assert {:shutdown, {:parent_down, _}} = exit_reason
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
      assert child_state.parent == nil
      assert child_state.orphaned_from.pid == parent_pid
      assert Map.get(child_state.agent.state, :__parent__) == nil
      assert child_state.agent.state.__orphaned_from__.id == "parent-continue-1"

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
      assert event.parent_pid == parent_pid
      assert event.tag == :worker
      assert event.meta == %{}
      assert event.reason in [:normal, :noproc]
      assert event.parent_available == false
      assert event.can_emit_to_parent == false
      assert event.orphaned_from_id == "parent-orphan-1"
      assert child_state.parent == nil
      assert child_state.orphaned_from.id == "parent-orphan-1"
      assert Map.get(child_state.agent.state, :__parent__) == nil
      assert child_state.agent.state.__orphaned_from__.pid == parent_pid

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

      child_ref = Process.monitor(child_pid)

      Process.exit(parent_pid, :kill)

      # Child should stop when parent dies - reason may be :killed or :noproc
      # depending on timing (whether parent is still dying or already dead).
      # All parent-down reasons are wrapped as {:shutdown, {:parent_down, _}}
      # so supervisors with :transient restart policy do not restart the child.
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, exit_reason}, 1000

      assert {:shutdown, {:parent_down, inner}} = exit_reason
      assert inner in [:killed, :noproc]
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

    test "rebinds restarted child info when child restarts", %{jido: jido} do
      parent_id = unique_id("spawn-parent")
      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      signal =
        Signal.new!(
          "spawn_agent",
          %{module: ChildAgent, tag: :restarting_child, restart: :permanent},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(parent_pid, signal)

      child_info = await_child(parent_pid, :restarting_child)
      child_pid = child_info.pid
      child_ref = Process.monitor(child_pid)

      GenServer.stop(child_pid, :boom)
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, :boom}, 500

      eventually(fn ->
        case AgentServer.state(parent_pid) do
          {:ok, state} ->
            case Map.get(state.children, :restarting_child) do
              %{pid: pid} when is_pid(pid) -> pid != child_pid
              _ -> false
            end

          _ ->
            false
        end
      end)

      restarted_child = await_child(parent_pid, :restarting_child, 1000)
      refute restarted_child.pid == child_pid
      assert restarted_child.id == child_info.id
      assert restarted_child.tag == :restarting_child
      assert Jido.whereis(jido, child_info.id) == restarted_child.pid

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), restarted_child.pid)
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

  describe "AdoptChild directive" do
    test "adopts an orphaned child by id and restores parent communication", %{jido: jido} do
      old_parent_id = unique_id("old-parent")
      replacement_parent_id = unique_id("replacement-parent")
      child_id = unique_id("adoptable-child")

      {:ok, old_parent_pid} = AgentServer.start(agent: ParentAgent, id: old_parent_id, jido: jido)

      spawn_signal =
        Signal.new!(
          "spawn_agent",
          %{
            module: ChildAgent,
            tag: :recoverable,
            opts: %{id: child_id, on_parent_death: :emit_orphan},
            meta: %{role: "worker"}
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(old_parent_pid, spawn_signal)
      child_info = await_child(old_parent_pid, :recoverable)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), old_parent_pid)

      eventually_state(child_info.pid, fn state ->
        state.parent == nil and state.orphaned_from.id == old_parent_id and
          length(state.agent.state.orphan_events) == 1
      end)

      {:ok, replacement_parent_pid} =
        AgentServer.start(agent: ParentAgent, id: replacement_parent_id, jido: jido)

      adopt_signal =
        Signal.new!(
          "adopt_child",
          %{child: child_id, tag: :recovered, meta: %{restored: true}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, adopt_signal)

      eventually(fn ->
        case AgentServer.state(replacement_parent_pid) do
          {:ok, state} -> Map.has_key?(state.children, :recovered)
          _ -> false
        end
      end)

      {:ok, replacement_parent_state} = AgentServer.state(replacement_parent_pid)
      adopted_child = replacement_parent_state.children.recovered
      assert adopted_child.id == child_id
      assert adopted_child.tag == :recovered

      {:ok, child_state} = AgentServer.state(child_info.pid)
      assert child_state.parent.id == replacement_parent_id
      assert child_state.parent.pid == replacement_parent_pid
      assert child_state.parent.tag == :recovered
      assert child_state.parent.meta == %{restored: true}
      assert child_state.orphaned_from == nil
      assert child_state.agent.state.__parent__.id == replacement_parent_id
      assert Map.get(child_state.agent.state, :__orphaned_from__) == nil

      reply = Directive.emit_to_parent(%{state: child_state.agent.state}, %{type: "child.reply"})
      assert %Directive.Emit{dispatch: {:pid, opts}} = reply
      assert opts[:target] == replacement_parent_pid

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), replacement_parent_pid)

      eventually_state(child_info.pid, fn state ->
        state.parent == nil and state.orphaned_from.id == replacement_parent_id and
          length(state.agent.state.orphan_events) == 2
      end)

      {:ok, reorphaned_state} = AgentServer.state(child_info.pid)
      [_, second_event] = reorphaned_state.agent.state.orphan_events
      assert second_event.parent_id == replacement_parent_id

      GenServer.stop(child_info.pid)
    end

    test "rehydrates the adopted parent after the child restarts", %{jido: jido} do
      original_parent_id = unique_id("original-parent")
      replacement_parent_id = unique_id("replacement-parent")
      child_id = unique_id("restartable-child")

      {:ok, original_parent_pid} =
        AgentServer.start(agent: ParentAgent, id: original_parent_id, jido: jido)

      spawn_signal =
        Signal.new!(
          "spawn_agent",
          %{
            module: ChildAgent,
            tag: :recoverable,
            opts: %{id: child_id, on_parent_death: :continue}
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(original_parent_pid, spawn_signal)
      child_info = await_child(original_parent_pid, :recoverable)
      original_child_pid = child_info.pid
      original_child_ref = Process.monitor(original_child_pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), original_parent_pid)

      eventually_state(original_child_pid, fn state ->
        state.parent == nil and state.orphaned_from.id == original_parent_id
      end)

      {:ok, replacement_parent_pid} =
        AgentServer.start(agent: ParentAgent, id: replacement_parent_id, jido: jido)

      adopt_signal =
        Signal.new!(
          "adopt_child",
          %{child: child_id, tag: :recovered, meta: %{restored: true}},
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, adopt_signal)

      eventually(fn ->
        case Jido.get_children(replacement_parent_pid) do
          {:ok, children} -> Map.get(children, :recovered) == original_child_pid
          _ -> false
        end
      end)

      GenServer.stop(original_child_pid, :boom)
      assert_receive {:DOWN, ^original_child_ref, :process, ^original_child_pid, :boom}, 1_000

      eventually(fn ->
        case Jido.get_children(replacement_parent_pid) do
          {:ok, children} ->
            case Map.get(children, :recovered) do
              pid when is_pid(pid) -> pid != original_child_pid
              _ -> false
            end

          _ ->
            false
        end
      end)

      restarted_child = await_child(replacement_parent_pid, :recovered, 1_000)
      refute restarted_child.pid == original_child_pid
      assert restarted_child.id == child_id
      assert Jido.whereis(jido, child_id) == restarted_child.pid

      {:ok, restarted_state} = AgentServer.state(restarted_child.pid)
      assert restarted_state.parent.id == replacement_parent_id
      assert restarted_state.parent.pid == replacement_parent_pid
      assert restarted_state.parent.tag == :recovered
      assert restarted_state.parent.meta == %{restored: true}
      assert restarted_state.orphaned_from == nil
      assert restarted_state.agent.state.__parent__.id == replacement_parent_id
      assert Map.get(restarted_state.agent.state, :__orphaned_from__) == nil

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), restarted_child.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), replacement_parent_pid)
    end

    test "does not adopt a child that is already attached", %{jido: jido} do
      parent_id = unique_id("attached-parent")
      adopter_id = unique_id("adopter")

      {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)
      {:ok, adopter_pid} = AgentServer.start(agent: ParentAgent, id: adopter_id, jido: jido)

      {:ok, child_pid} =
        AgentServer.start(
          agent: ChildAgent,
          id: unique_id("attached-child"),
          parent: ParentRef.new!(%{pid: parent_pid, id: parent_id, tag: :worker}),
          jido: jido
        )

      adopt_signal =
        Signal.new!("adopt_child", %{child: child_pid, tag: :claimed}, source: "/test")

      {:ok, _agent} = AgentServer.call(adopter_pid, adopt_signal)

      {:ok, adopter_state} = AgentServer.state(adopter_pid)
      refute Map.has_key?(adopter_state.children, :claimed)

      {:ok, child_state} = AgentServer.state(child_pid)
      assert child_state.parent.id == parent_id

      GenServer.stop(child_pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), adopter_pid)
    end

    test "does not adopt a dead child pid", %{jido: jido} do
      adopter_id = unique_id("adopter")
      {:ok, adopter_pid} = AgentServer.start(agent: ParentAgent, id: adopter_id, jido: jido)

      child_pid = spawn(fn -> :ok end)
      eventually(fn -> not Process.alive?(child_pid) end)

      adopt_signal =
        Signal.new!("adopt_child", %{child: child_pid, tag: :missing}, source: "/test")

      {:ok, _agent} = AgentServer.call(adopter_pid, adopt_signal)

      {:ok, adopter_state} = AgentServer.state(adopter_pid)
      refute Map.has_key?(adopter_state.children, :missing)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), adopter_pid)
    end

    test "does not adopt when the requested tag is already in use", %{jido: jido} do
      parent_id = unique_id("parent")
      replacement_parent_id = unique_id("replacement-parent")
      child_id = unique_id("recover-child")

      {:ok, old_parent_pid} = AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido)

      spawn_signal =
        Signal.new!(
          "spawn_agent",
          %{
            module: ChildAgent,
            tag: :recoverable,
            opts: %{id: child_id, on_parent_death: :continue}
          },
          source: "/test"
        )

      {:ok, _agent} = AgentServer.call(old_parent_pid, spawn_signal)
      child_info = await_child(old_parent_pid, :recoverable)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), old_parent_pid)

      eventually_state(child_info.pid, fn state -> state.parent == nil end)

      {:ok, replacement_parent_pid} =
        AgentServer.start(agent: ParentAgent, id: replacement_parent_id, jido: jido)

      occupied_signal =
        Signal.new!("spawn_agent", %{module: ChildAgent, tag: :occupied}, source: "/test")

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, occupied_signal)
      occupied_child = await_child(replacement_parent_pid, :occupied)

      adopt_signal =
        Signal.new!("adopt_child", %{child: child_id, tag: :occupied}, source: "/test")

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, adopt_signal)

      {:ok, replacement_parent_state} = AgentServer.state(replacement_parent_pid)
      assert replacement_parent_state.children.occupied.pid == occupied_child.pid

      refute Enum.any?(replacement_parent_state.children, fn {_tag, info} ->
               info.id == child_id
             end)

      {:ok, orphaned_child_state} = AgentServer.state(child_info.pid)
      assert orphaned_child_state.parent == nil

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), occupied_child.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), replacement_parent_pid)
      GenServer.stop(child_info.pid)
    end

    test "does not adopt an unknown child id", %{jido: jido} do
      adopter_id = unique_id("adopter")
      {:ok, adopter_pid} = AgentServer.start(agent: ParentAgent, id: adopter_id, jido: jido)

      adopt_signal =
        Signal.new!("adopt_child", %{child: "missing-child", tag: :missing}, source: "/test")

      {:ok, _agent} = AgentServer.call(adopter_pid, adopt_signal)

      {:ok, adopter_state} = AgentServer.state(adopter_pid)
      refute Map.has_key?(adopter_state.children, :missing)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), adopter_pid)
    end
  end

  describe "partitioned hierarchy" do
    test "spawned children inherit the parent partition by default", %{jido: jido} do
      parent_id = unique_id("partition-parent")

      {:ok, parent_pid} =
        AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido, partition: :alpha)

      spawn_signal =
        Signal.new!("spawn_agent", %{module: ChildAgent, tag: :worker}, source: "/test")

      {:ok, _agent} = AgentServer.call(parent_pid, spawn_signal)

      parent_state =
        eventually_state(parent_pid, fn state ->
          Map.has_key?(state.children, :worker)
        end)

      child_info = parent_state.children.worker

      assert child_info.partition == :alpha
      assert Jido.whereis(jido, child_info.id, partition: :alpha) == child_info.pid
      assert Jido.whereis(jido, child_info.id) == nil

      {:ok, child_state} = AgentServer.state(child_info.pid)
      assert child_state.partition == :alpha
      assert child_state.agent.state.__partition__ == :alpha
      assert child_state.parent.partition == :alpha

      assert {:ok, binding} =
               Jido.RuntimeStore.fetch(jido, :relationships, {:partition, :alpha, child_info.id})

      assert binding.parent_id == parent_id
      assert binding.parent_partition == :alpha

      GenServer.stop(child_info.pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "adoption by child id resolves only within the parent's partition", %{jido: jido} do
      parent_id = unique_id("partition-adopter")
      child_id = unique_id("shared-child")

      {:ok, parent_pid} =
        AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido, partition: :alpha)

      {:ok, alpha_child_pid} =
        AgentServer.start(agent: ChildAgent, id: child_id, jido: jido, partition: :alpha)

      {:ok, beta_child_pid} =
        AgentServer.start(agent: ChildAgent, id: child_id, jido: jido, partition: :beta)

      adopt_signal =
        Signal.new!("adopt_child", %{child: child_id, tag: :worker}, source: "/test")

      {:ok, _agent} = AgentServer.call(parent_pid, adopt_signal)

      eventually_state(alpha_child_pid, fn state ->
        match?(%ParentRef{id: ^parent_id, partition: :alpha}, state.parent)
      end)

      {:ok, beta_child_state} = AgentServer.state(beta_child_pid)
      assert beta_child_state.parent == nil

      assert {:ok, binding} =
               Jido.RuntimeStore.fetch(jido, :relationships, {:partition, :alpha, child_id})

      assert binding.parent_id == parent_id
      assert binding.parent_partition == :alpha

      assert Jido.RuntimeStore.fetch(jido, :relationships, {:partition, :beta, child_id}) ==
               :error

      GenServer.stop(alpha_child_pid)
      GenServer.stop(beta_child_pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end

    test "cross-partition adoption requires an explicit pid and preserves child partition", %{
      jido: jido
    } do
      parent_id = unique_id("cross-partition-parent")
      child_id = unique_id("cross-partition-child")

      {:ok, parent_pid} =
        AgentServer.start(agent: ParentAgent, id: parent_id, jido: jido, partition: :alpha)

      {:ok, child_pid} =
        AgentServer.start(agent: ChildAgent, id: child_id, jido: jido, partition: :beta)

      adopt_signal =
        Signal.new!("adopt_child", %{child: child_pid, tag: :cross}, source: "/test")

      {:ok, _agent} = AgentServer.call(parent_pid, adopt_signal)

      eventually_state(child_pid, fn state ->
        state.partition == :beta and
          match?(%ParentRef{id: ^parent_id, partition: :alpha}, state.parent)
      end)

      parent_state =
        eventually_state(parent_pid, fn state ->
          match?(%ChildInfo{partition: :beta}, Map.get(state.children, :cross))
        end)

      assert parent_state.children.cross.pid == child_pid
      assert parent_state.children.cross.partition == :beta
      assert Jido.whereis(jido, child_id, partition: :beta) == child_pid
      assert Jido.whereis(jido, child_id, partition: :alpha) == nil

      assert {:ok, binding} =
               Jido.RuntimeStore.fetch(jido, :relationships, {:partition, :beta, child_id})

      assert binding.parent_id == parent_id
      assert binding.parent_partition == :alpha

      GenServer.stop(child_pid)
      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)
    end
  end
end
