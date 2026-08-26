defmodule JidoExampleTest.OrphanLifecycleTest do
  @moduledoc """
  Example test demonstrating the full orphan lifecycle and explicit adoption.

  This example is intentionally advanced. It shows how to let a child agent
  survive the death of its logical parent, observe the orphan transition, and
  explicitly attach that live child to a replacement coordinator.

  This test proves:
  - `SpawnAgent` can create a child with `on_parent_death: :emit_orphan`
  - `emit_to_parent/3` works normally while the child is attached
  - parent death clears current parent routing immediately
  - the child receives `jido.agent.orphaned` after detachment
  - orphan state preserves former-parent provenance
  - `Directive.adopt_child/3` restores parent linkage and `Jido.get_children/1`
  - the adopted child can resume sending results to the new parent
  - an adopted child restart rehydrates the adopted parent binding
  - a `RuntimeStore` process restart inside the same Jido instance retains bindings
  - a second parent death re-triggers the orphan lifecycle

  ## Run

      mix test --include example test/examples/runtime/orphan_lifecycle_test.exs

  ## Why This Matters

  Jido parent/child relationships are logical, not OTP supervisory ancestry.
  That means you can choose whether a child should disappear with its
  coordinator or keep running and become orphaned.

  The orphan path is powerful, but it is not the default. Use it when the child
  owns durable work that should outlive the original coordinator.
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 30_000

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.ParentRef
  alias Jido.RuntimeStore
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS: Coordinator-side orchestration
  # ===========================================================================

  defmodule SpawnRecoverableWorkerAction do
    @moduledoc false
    use Jido.Action,
      name: "spawn_recoverable_worker",
      schema: [
        tag: [type: :atom, required: true],
        child_id: [type: :string, required: true]
      ]

    def run(%{tag: tag, child_id: child_id}, context) do
      directive =
        Directive.spawn_agent(JidoExampleTest.OrphanLifecycleTest.RecoverableWorkerAgent, tag,
          opts: %{id: child_id, on_parent_death: :emit_orphan},
          meta: %{role: "recoverable"}
        )

      spawned = Map.get(context.state, :spawned_children, [])
      {:ok, %{spawned_children: spawned ++ [child_id]}, [directive]}
    end
  end

  defmodule TrackChildStartedAction do
    @moduledoc false
    use Jido.Action,
      name: "track_child_started",
      schema: [
        pid: [type: :any, required: true],
        child_id: [type: :string, required: true],
        tag: [type: :atom, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(params, context) do
      started_children = Map.get(context.state, :started_children, [])

      event = %{
        pid: params.pid,
        child_id: params.child_id,
        tag: params.tag,
        meta: params.meta
      }

      {:ok, %{started_children: started_children ++ [event]}}
    end
  end

  defmodule ReceiveWorkerMessageAction do
    @moduledoc false
    use Jido.Action,
      name: "receive_worker_message",
      schema: [
        text: [type: :string, required: true],
        current_parent_id: [type: :string, required: true]
      ]

    def run(params, context) do
      messages = Map.get(context.state, :received_messages, [])
      {:ok, %{received_messages: messages ++ [params]}}
    end
  end

  defmodule AdoptWorkerAction do
    @moduledoc false
    use Jido.Action,
      name: "adopt_worker",
      schema: [
        child: [type: :string, required: true],
        tag: [type: :atom, required: true],
        meta: [type: :map, default: %{}]
      ]

    def run(%{child: child, tag: tag, meta: meta}, _context) do
      {:ok, %{}, [Directive.adopt_child(child, tag, meta: meta)]}
    end
  end

  # ===========================================================================
  # ACTIONS: Worker-side reporting and orphan handling
  # ===========================================================================

  defmodule ReportToParentAction do
    @moduledoc false
    use Jido.Action,
      name: "report_to_parent",
      schema: [
        text: [type: :string, required: true]
      ]

    def run(%{text: text}, context) do
      parent_ref = Map.get(context.state, :__parent__)

      signal =
        Signal.new!(
          "worker.message",
          %{text: text, current_parent_id: parent_ref && parent_ref.id},
          source: "/worker"
        )

      emit_directive = Directive.emit_to_parent(%{state: context.state}, signal)
      reports = Map.get(context.state, :reports, [])

      report = %{
        text: text,
        delivered_to_parent: not is_nil(emit_directive),
        current_parent_id: parent_ref && parent_ref.id
      }

      {:ok, %{reports: reports ++ [report]}, List.wrap(emit_directive)}
    end
  end

  defmodule HandleOrphanedAction do
    @moduledoc false
    use Jido.Action,
      name: "handle_orphaned",
      schema: [
        parent_id: [type: :string, required: true],
        parent_pid: [type: :any, required: true],
        tag: [type: :any, required: true],
        meta: [type: :map, default: %{}],
        reason: [type: :any, required: true]
      ]

    def run(params, context) do
      orphan_events = Map.get(context.state, :orphan_events, [])
      former_parent = Map.get(context.state, :__orphaned_from__)

      can_emit_to_parent =
        Directive.emit_to_parent(
          %{state: context.state},
          Signal.new!("worker.orphan.check", %{}, source: "/worker")
        ) != nil

      event = %{
        parent_id: params.parent_id,
        parent_pid: params.parent_pid,
        tag: params.tag,
        meta: params.meta,
        reason: params.reason,
        parent_available: not is_nil(Map.get(context.state, :__parent__)),
        orphaned_from_id: former_parent && former_parent.id,
        can_emit_to_parent: can_emit_to_parent
      }

      {:ok, %{orphan_events: orphan_events ++ [event]}}
    end
  end

  # ===========================================================================
  # AGENTS: Coordinator and recoverable worker
  # ===========================================================================

  defmodule CoordinatorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "orphan_lifecycle_coordinator",
      schema: [
        spawned_children: [type: {:list, :string}, default: []],
        started_children: [type: {:list, :map}, default: []],
        received_messages: [type: {:list, :map}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"spawn_recoverable_worker", SpawnRecoverableWorkerAction},
        {"adopt_worker", AdoptWorkerAction},
        {"jido.agent.child.started", TrackChildStartedAction},
        {"worker.message", ReceiveWorkerMessageAction}
      ]
    end
  end

  defmodule RecoverableWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "recoverable_worker",
      schema: [
        reports: [type: {:list, :map}, default: []],
        orphan_events: [type: {:list, :map}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"worker.report", ReportToParentAction},
        {"jido.agent.orphaned", HandleOrphanedAction}
      ]
    end
  end

  # ===========================================================================
  # HELPERS
  # ===========================================================================

  defp await_child_pid(parent_pid, tag, timeout \\ 1_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_child_pid(parent_pid, tag, deadline)
  end

  defp do_await_child_pid(parent_pid, tag, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      flunk("Timed out waiting for child #{inspect(tag)}")
    end

    case Jido.get_children(parent_pid) do
      {:ok, children} when is_map_key(children, tag) ->
        children[tag]

      {:ok, _children} ->
        Process.sleep(10)
        do_await_child_pid(parent_pid, tag, deadline)

      {:error, _reason} ->
        flunk("Parent process died while waiting for child #{inspect(tag)}")
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "orphan lifecycle" do
    test "child becomes orphaned, is adopted, and can be orphaned again", %{jido: jido} do
      original_parent_id = unique_id("coordinator")
      replacement_parent_id = unique_id("replacement")
      child_id = unique_id("recoverable-worker")

      {:ok, original_parent_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: original_parent_id)

      spawn_signal =
        Signal.new!(
          "spawn_recoverable_worker",
          %{tag: :primary_worker, child_id: child_id},
          source: "/example"
        )

      {:ok, _agent} = AgentServer.call(original_parent_pid, spawn_signal)

      child_pid = await_child_pid(original_parent_pid, :primary_worker)

      eventually_state(original_parent_pid, fn state ->
        length(state.agent.state.started_children) == 1
      end)

      attached_report =
        Signal.new!("worker.report", %{text: "attached hello"}, source: "/example")

      {:ok, _agent} = AgentServer.call(child_pid, attached_report)

      eventually_state(original_parent_pid, fn state ->
        length(state.agent.state.received_messages) == 1
      end)

      {:ok, original_parent_state} = AgentServer.state(original_parent_pid)
      [attached_message] = original_parent_state.agent.state.received_messages
      assert attached_message.text == "attached hello"
      assert attached_message.current_parent_id == original_parent_id

      {:ok, attached_worker_state} = AgentServer.state(child_pid)
      [attached_report_entry] = attached_worker_state.agent.state.reports
      assert attached_report_entry.delivered_to_parent == true
      assert attached_report_entry.current_parent_id == original_parent_id

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), original_parent_pid)

      eventually_state(child_pid, fn state ->
        state.parent == nil and
          Map.get(state.agent.state, :__parent__) == nil and
          match?(%ParentRef{id: ^original_parent_id}, state.orphaned_from) and
          length(state.agent.state.orphan_events) == 1
      end)

      {:ok, orphaned_state} = AgentServer.state(child_pid)
      [first_orphan_event] = orphaned_state.agent.state.orphan_events

      assert first_orphan_event.parent_id == original_parent_id
      assert first_orphan_event.parent_pid == original_parent_pid
      assert first_orphan_event.tag == :primary_worker
      assert first_orphan_event.meta == %{role: "recoverable"}
      assert first_orphan_event.parent_available == false
      assert first_orphan_event.orphaned_from_id == original_parent_id
      assert first_orphan_event.can_emit_to_parent == false

      assert orphaned_state.parent == nil
      assert orphaned_state.orphaned_from.id == original_parent_id
      assert Map.get(orphaned_state.agent.state, :__parent__) == nil
      assert orphaned_state.agent.state.__orphaned_from__.id == original_parent_id

      orphaned_emit =
        Directive.emit_to_parent(
          %{state: orphaned_state.agent.state},
          Signal.new!("worker.message", %{text: "orphaned"}, source: "/worker")
        )

      assert orphaned_emit == nil

      orphaned_report =
        Signal.new!("worker.report", %{text: "orphaned attempt"}, source: "/example")

      {:ok, _agent} = AgentServer.call(child_pid, orphaned_report)

      eventually_state(child_pid, fn state ->
        length(state.agent.state.reports) == 2
      end)

      {:ok, after_orphan_report_state} = AgentServer.state(child_pid)
      [_attached_report, orphaned_report_entry] = after_orphan_report_state.agent.state.reports
      assert orphaned_report_entry.delivered_to_parent == false
      assert orphaned_report_entry.current_parent_id == nil

      {:ok, replacement_parent_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: replacement_parent_id)

      adopt_signal =
        Signal.new!(
          "adopt_worker",
          %{child: child_id, tag: :recovered_worker, meta: %{role: "replacement"}},
          source: "/example"
        )

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, adopt_signal)

      eventually(fn ->
        case Jido.get_children(replacement_parent_pid) do
          {:ok, children} -> Map.get(children, :recovered_worker) == child_pid
          _ -> false
        end
      end)

      {:ok, adopted_children} = Jido.get_children(replacement_parent_pid)
      assert adopted_children.recovered_worker == child_pid

      {:ok, adopted_state} = AgentServer.state(child_pid)
      assert adopted_state.parent.id == replacement_parent_id
      assert adopted_state.parent.pid == replacement_parent_pid
      assert adopted_state.parent.tag == :recovered_worker
      assert adopted_state.parent.meta == %{role: "replacement"}
      assert adopted_state.orphaned_from == nil
      assert adopted_state.agent.state.__parent__.id == replacement_parent_id
      assert Map.get(adopted_state.agent.state, :__orphaned_from__) == nil

      adopted_report =
        Signal.new!("worker.report", %{text: "adopted hello"}, source: "/example")

      {:ok, _agent} = AgentServer.call(child_pid, adopted_report)

      eventually_state(replacement_parent_pid, fn state ->
        length(state.agent.state.received_messages) == 1
      end)

      {:ok, replacement_parent_state} = AgentServer.state(replacement_parent_pid)
      [adopted_message] = replacement_parent_state.agent.state.received_messages
      assert adopted_message.text == "adopted hello"
      assert adopted_message.current_parent_id == replacement_parent_id

      {:ok, after_adoption_worker_state} = AgentServer.state(child_pid)

      [_attached_report, _orphaned_report, adopted_report_entry] =
        after_adoption_worker_state.agent.state.reports

      assert adopted_report_entry.delivered_to_parent == true
      assert adopted_report_entry.current_parent_id == replacement_parent_id

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), replacement_parent_pid)

      eventually_state(child_pid, fn state ->
        state.parent == nil and
          match?(%ParentRef{id: ^replacement_parent_id}, state.orphaned_from) and
          length(state.agent.state.orphan_events) == 2
      end)

      {:ok, reorphaned_state} = AgentServer.state(child_pid)
      [_first_orphan_event, second_orphan_event] = reorphaned_state.agent.state.orphan_events

      assert second_orphan_event.parent_id == replacement_parent_id
      assert second_orphan_event.parent_pid == replacement_parent_pid
      assert second_orphan_event.tag == :recovered_worker
      assert second_orphan_event.meta == %{role: "replacement"}
      assert second_orphan_event.parent_available == false
      assert second_orphan_event.can_emit_to_parent == false

      GenServer.stop(child_pid)
    end

    test "adopted children keep the adopted parent after a restart", %{jido: jido} do
      original_parent_id = unique_id("restart-original")
      replacement_parent_id = unique_id("restart-replacement")
      child_id = unique_id("restart-worker")

      {:ok, original_parent_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: original_parent_id)

      spawn_signal =
        Signal.new!(
          "spawn_recoverable_worker",
          %{tag: :primary_worker, child_id: child_id},
          source: "/example"
        )

      {:ok, _agent} = AgentServer.call(original_parent_pid, spawn_signal)
      child_pid = await_child_pid(original_parent_pid, :primary_worker)
      child_ref = Process.monitor(child_pid)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), original_parent_pid)

      eventually_state(child_pid, fn state ->
        state.parent == nil and
          match?(%ParentRef{id: ^original_parent_id}, state.orphaned_from)
      end)

      {:ok, replacement_parent_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: replacement_parent_id)

      adopt_signal =
        Signal.new!(
          "adopt_worker",
          %{child: child_id, tag: :recovered_worker, meta: %{role: "replacement"}},
          source: "/example"
        )

      {:ok, _agent} = AgentServer.call(replacement_parent_pid, adopt_signal)

      eventually(fn ->
        case Jido.get_children(replacement_parent_pid) do
          {:ok, children} -> Map.get(children, :recovered_worker) == child_pid
          _ -> false
        end
      end)

      GenServer.stop(child_pid, :boom)
      assert_receive {:DOWN, ^child_ref, :process, ^child_pid, :boom}, 1_000

      eventually(fn ->
        case Jido.get_children(replacement_parent_pid) do
          {:ok, children} ->
            case Map.get(children, :recovered_worker) do
              pid when is_pid(pid) -> pid != child_pid
              _ -> false
            end

          _ ->
            false
        end
      end)

      restarted_child_pid = await_child_pid(replacement_parent_pid, :recovered_worker, 1_000)
      refute restarted_child_pid == child_pid

      {:ok, restarted_state} = AgentServer.state(restarted_child_pid)
      assert restarted_state.parent.id == replacement_parent_id
      assert restarted_state.parent.pid == replacement_parent_pid
      assert restarted_state.parent.tag == :recovered_worker
      assert restarted_state.parent.meta == %{role: "replacement"}
      assert restarted_state.orphaned_from == nil
      assert restarted_state.agent.state.__parent__.id == replacement_parent_id
      assert Map.get(restarted_state.agent.state, :__orphaned_from__) == nil

      adopted_report =
        Signal.new!("worker.report", %{text: "after restart"}, source: "/example")

      {:ok, _agent} = AgentServer.call(restarted_child_pid, adopted_report)

      eventually_state(replacement_parent_pid, fn state ->
        Enum.any?(state.agent.state.received_messages, fn message ->
          message.text == "after restart" and
            message.current_parent_id == replacement_parent_id
        end)
      end)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), replacement_parent_pid)

      eventually_state(restarted_child_pid, fn state ->
        state.parent == nil and
          match?(%ParentRef{id: ^replacement_parent_id}, state.orphaned_from) and
          length(state.agent.state.orphan_events) == 1
      end)

      GenServer.stop(restarted_child_pid)
    end

    test "repeated orphan/adopt/restart cycles keep bindings stable", %{jido: jido} do
      original_parent_id = unique_id("stress-original")
      child_id = unique_id("stress-worker")
      runtime_store = Jido.runtime_store_name(jido)

      {:ok, original_parent_pid} =
        Jido.start_agent(jido, CoordinatorAgent, id: original_parent_id)

      spawn_signal =
        Signal.new!(
          "spawn_recoverable_worker",
          %{tag: :primary_worker, child_id: child_id},
          source: "/example"
        )

      {:ok, _agent} = AgentServer.call(original_parent_pid, spawn_signal)
      child_pid = await_child_pid(original_parent_pid, :primary_worker)

      assert {:ok, %{parent_id: ^original_parent_id, tag: :primary_worker}} =
               RuntimeStore.fetch(jido, :relationships, child_id)

      DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), original_parent_pid)

      eventually_state(child_pid, fn state ->
        state.parent == nil and
          match?(%ParentRef{id: ^original_parent_id}, state.orphaned_from)
      end)

      assert :error == RuntimeStore.fetch(jido, :relationships, child_id)

      cycles = [
        %{parent_id: unique_id("stress-replacement"), tag: :cycle_one, meta: %{cycle: 1}},
        %{parent_id: unique_id("stress-replacement"), tag: :cycle_two, meta: %{cycle: 2}}
      ]

      final_child_pid =
        Enum.reduce(cycles, child_pid, fn %{parent_id: parent_id, tag: tag, meta: meta}, pid ->
          {:ok, parent_pid} = Jido.start_agent(jido, CoordinatorAgent, id: parent_id)

          adopt_signal =
            Signal.new!(
              "adopt_worker",
              %{child: child_id, tag: tag, meta: meta},
              source: "/example"
            )

          {:ok, _agent} = AgentServer.call(parent_pid, adopt_signal)

          eventually(fn ->
            case Jido.get_children(parent_pid) do
              {:ok, children} -> Map.get(children, tag) == pid
              _ -> false
            end
          end)

          assert {:ok, %{parent_id: ^parent_id, tag: ^tag, meta: ^meta}} =
                   RuntimeStore.fetch(jido, :relationships, child_id)

          if meta.cycle == 1 do
            runtime_store_pid = Process.whereis(runtime_store)
            runtime_store_ref = Process.monitor(runtime_store_pid)

            Process.exit(runtime_store_pid, :kill)

            assert_receive {:DOWN, ^runtime_store_ref, :process, ^runtime_store_pid, :killed},
                           1_000

            eventually(fn ->
              case Process.whereis(runtime_store) do
                restarted_pid when is_pid(restarted_pid) -> restarted_pid != runtime_store_pid
                _ -> false
              end
            end)

            assert {:ok, %{parent_id: ^parent_id, tag: ^tag, meta: ^meta}} =
                     RuntimeStore.fetch(jido, :relationships, child_id)
          end

          report_signal =
            Signal.new!("worker.report", %{text: "cycle #{meta.cycle}"}, source: "/example")

          {:ok, _agent} = AgentServer.call(pid, report_signal)

          eventually_state(parent_pid, fn state ->
            Enum.any?(state.agent.state.received_messages, fn message ->
              message.text == "cycle #{meta.cycle}" and message.current_parent_id == parent_id
            end)
          end)

          child_ref = Process.monitor(pid)
          GenServer.stop(pid, :boom)
          assert_receive {:DOWN, ^child_ref, :process, ^pid, :boom}, 1_000

          eventually(fn ->
            case Jido.get_children(parent_pid) do
              {:ok, children} ->
                case Map.get(children, tag) do
                  restarted_pid when is_pid(restarted_pid) -> restarted_pid != pid
                  _ -> false
                end

              _ ->
                false
            end
          end)

          restarted_child_pid = await_child_pid(parent_pid, tag, 1_000)

          assert {:ok, %{parent_id: ^parent_id, tag: ^tag, meta: ^meta}} =
                   RuntimeStore.fetch(jido, :relationships, child_id)

          {:ok, restarted_state} = AgentServer.state(restarted_child_pid)
          assert restarted_state.parent.id == parent_id
          assert restarted_state.parent.pid == parent_pid
          assert restarted_state.parent.tag == tag
          assert restarted_state.parent.meta == meta

          DynamicSupervisor.terminate_child(Jido.agent_supervisor_name(jido), parent_pid)

          eventually_state(restarted_child_pid, fn state ->
            state.parent == nil and match?(%ParentRef{id: ^parent_id}, state.orphaned_from)
          end)

          assert :error == RuntimeStore.fetch(jido, :relationships, child_id)

          restarted_child_pid
        end)

      GenServer.stop(final_child_pid)
    end
  end
end
