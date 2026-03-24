defmodule JidoTest.Pod.RuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Pod.Topology
  alias Jido.Storage.ETS

  @planner_manager :pod_runtime_planner_members
  @reviewer_manager :pod_runtime_reviewer_members
  @nested_pod_manager :pod_runtime_nested_pods
  @recursive_pod_manager :pod_runtime_recursive_pods
  @pod_manager :pod_runtime_review_pods

  defmodule PodWorker do
    @moduledoc false
    use Jido.Agent,
      name: "pod_runtime_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule ReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "runtime_review_pod",
      topology:
        Topology.new!(
          name: "runtime_review_pod",
          nodes: %{
            planner: %{
              agent: PodWorker,
              manager: :pod_runtime_planner_members,
              activation: :eager,
              meta: %{role: "planner"},
              initial_state: %{role: "planner"}
            },
            reviewer: %{
              agent: PodWorker,
              manager: :pod_runtime_reviewer_members,
              activation: :lazy,
              meta: %{role: "reviewer"},
              initial_state: %{role: "reviewer"}
            }
          },
          links: [{:owns, :planner, :reviewer}]
        )
  end

  defmodule HierarchicalReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "hierarchical_runtime_review_pod",
      topology: %{
        nested: %{
          module: ReviewPod,
          manager: :pod_runtime_nested_pods,
          kind: :pod,
          activation: :eager
        }
      }
  end

  defmodule RecursiveReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "recursive_review_pod",
      topology: %{
        nested: %{
          module: __MODULE__,
          manager: :pod_runtime_recursive_pods,
          kind: :pod,
          activation: :eager
        }
      }
  end

  defmodule AlternateReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "alternate_review_pod",
      topology: %{
        editor: %{
          agent: PodWorker,
          manager: :pod_runtime_planner_members,
          activation: :eager,
          initial_state: %{role: "editor"}
        }
      }
  end

  defmodule PartialFailurePod do
    @moduledoc false
    use Jido.Pod,
      name: "partial_failure_pod",
      topology:
        Jido.Pod.Topology.new!(
          name: "partial_failure_pod",
          nodes: %{
            planner: %{
              agent: JidoTest.Pod.RuntimeTest.PodWorker,
              manager: :pod_runtime_planner_members,
              activation: :eager
            },
            nested: %{
              module: JidoTest.Pod.RuntimeTest.RecursiveReviewPod,
              manager: :pod_runtime_recursive_pods,
              kind: :pod,
              activation: :eager
            }
          },
          links: [{:depends_on, :nested, :planner}]
        )
  end

  defmodule ManagerMismatchPod do
    @moduledoc false
    use Jido.Pod,
      name: "manager_mismatch_pod",
      topology: %{
        nested: %{
          module: AlternateReviewPod,
          manager: :pod_runtime_nested_pods,
          kind: :pod,
          activation: :eager
        }
      }
  end

  setup %{jido: jido} do
    storage_table = :"pod_runtime_storage_#{System.unique_integer([:positive])}"

    {:ok, _planner_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @planner_manager,
          agent: PodWorker,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _reviewer_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @reviewer_manager,
          agent: PodWorker,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @pod_manager,
          agent: ReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    {:ok, _nested_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @nested_pod_manager,
          agent: ReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _recursive_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @recursive_pod_manager,
          agent: RecursiveReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @planner_manager})
      :persistent_term.erase({InstanceManager, @reviewer_manager})
      :persistent_term.erase({InstanceManager, @nested_pod_manager})
      :persistent_term.erase({InstanceManager, @recursive_pod_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "order-123"}
  end

  test "get eagerly reconciles roots and ensure_node adopts owned lazy nodes under their owner",
       %{
         pod_key: pod_key
       } do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert {:ok, %Pod.Topology{name: "runtime_review_pod"}} = Pod.fetch_topology(pod_pid)

    planner_key = {ReviewPod, pod_key, :planner}
    reviewer_key = {ReviewPod, pod_key, :reviewer}

    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)
    assert {:ok, ^planner_pid} = InstanceManager.lookup(@planner_manager, planner_key)
    assert :error = Pod.lookup_node(pod_pid, :reviewer)
    assert :error = InstanceManager.lookup(@reviewer_manager, reviewer_key)

    assert {:ok, snapshots} = Pod.nodes(pod_pid)
    assert snapshots.planner.status == :adopted
    assert snapshots.reviewer.status == :stopped

    assert {:ok, reviewer_pid} = Pod.ensure_node(pod_pid, :reviewer)
    assert {:ok, ^reviewer_pid} = Pod.lookup_node(pod_pid, :reviewer)
    assert {:ok, ^reviewer_pid} = InstanceManager.lookup(@reviewer_manager, reviewer_key)

    {:ok, manager_state} = AgentServer.state(pod_pid)
    assert manager_state.children.planner.pid == planner_pid
    refute Map.has_key?(manager_state.children, :reviewer)

    {:ok, planner_state} = AgentServer.state(planner_pid)
    assert planner_state.children.reviewer.pid == reviewer_pid
  end

  test "restored pod managers can re-adopt surviving eager nodes", %{pod_key: pod_key} do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(@pod_manager, pod_key)
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

    assert Process.alive?(planner_pid)
    assert {:ok, planner_state} = AgentServer.state(planner_pid)
    assert planner_state.parent == nil
    assert planner_state.orphaned_from.id == pod_key

    assert {:ok, restored_pid} = Pod.get(@pod_manager, pod_key)
    assert restored_pid != pod_pid
    assert {:ok, ^planner_pid} = Pod.lookup_node(restored_pid, :planner)

    planner_key = {ReviewPod, pod_key, :planner}
    assert {:ok, ^planner_pid} = InstanceManager.lookup(@planner_manager, planner_key)
  end

  test "thaw restores pod topology immediately and only root ownership needs pod-level re-adoption",
       %{
         pod_key: pod_key
       } do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)
    assert {:ok, reviewer_pid} = Pod.ensure_node(pod_pid, :reviewer)

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(@pod_manager, pod_key)
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

    assert Process.alive?(planner_pid)
    assert Process.alive?(reviewer_pid)

    assert {:ok, restored_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert {:ok, %Pod.Topology{name: "runtime_review_pod"}} = Pod.fetch_topology(restored_pid)

    assert {:ok, snapshots} = Pod.nodes(restored_pid)
    assert snapshots.planner.status == :running
    assert snapshots.planner.running_pid == planner_pid
    assert snapshots.planner.adopted_pid == nil
    assert snapshots.reviewer.status == :adopted
    assert snapshots.reviewer.running_pid == reviewer_pid
    assert snapshots.reviewer.adopted_pid == reviewer_pid

    assert {:ok, report} = Pod.reconcile(restored_pid)
    assert report.completed == [:planner]
    assert report.failed == []

    assert {:ok, snapshots} = Pod.nodes(restored_pid)
    assert snapshots.planner.status == :adopted
    assert snapshots.planner.adopted_pid == planner_pid
    assert snapshots.reviewer.status == :adopted
    assert snapshots.reviewer.adopted_pid == reviewer_pid
  end

  test "nested pod nodes run through their own pod runtime and attach into the parent hierarchy",
       %{
         jido: jido
       } do
    storage_table = :"pod_runtime_nested_storage_#{System.unique_integer([:positive])}"
    manager = :"pod_runtime_nested_pod_manager_#{System.unique_integer([:positive])}"

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: manager,
          agent: HierarchicalReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    assert {:ok, pid} = Pod.get(manager, "group-123")
    assert Process.alive?(pid)

    nested_key = {HierarchicalReviewPod, "group-123", :nested}
    nested_planner_key = {ReviewPod, nested_key, :planner}

    assert {:ok, nested_pid} = Pod.lookup_node(pid, :nested)
    assert {:ok, ^nested_pid} = InstanceManager.lookup(@nested_pod_manager, nested_key)
    assert {:ok, nested_planner_pid} = Pod.lookup_node(nested_pid, :planner)

    assert {:ok, ^nested_planner_pid} =
             InstanceManager.lookup(@planner_manager, nested_planner_key)

    {:ok, parent_state} = AgentServer.state(pid)
    assert parent_state.children.nested.pid == nested_pid

    {:ok, nested_state} = AgentServer.state(nested_pid)
    assert nested_state.children.planner.pid == nested_planner_pid
  end

  test "restored parent pods re-adopt surviving nested pod nodes", %{jido: jido} do
    storage_table = :"pod_runtime_nested_restore_storage_#{System.unique_integer([:positive])}"
    manager = :"pod_runtime_nested_restore_manager_#{System.unique_integer([:positive])}"

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: manager,
          agent: HierarchicalReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    assert {:ok, pod_pid} = Pod.get(manager, "group-restore")
    assert {:ok, nested_pid} = Pod.lookup_node(pod_pid, :nested)
    assert {:ok, nested_planner_pid} = Pod.lookup_node(nested_pid, :planner)

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(manager, "group-restore")
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

    assert Process.alive?(nested_pid)
    assert Process.alive?(nested_planner_pid)

    assert {:ok, nested_state} = AgentServer.state(nested_pid)
    assert nested_state.parent == nil
    assert nested_state.orphaned_from.id == "group-restore"

    assert {:ok, nested_planner_state} = AgentServer.state(nested_planner_pid)
    assert nested_planner_state.parent.pid == nested_pid

    assert {:ok, restored_pid} = Pod.get(manager, "group-restore")
    assert {:ok, ^nested_pid} = Pod.lookup_node(restored_pid, :nested)

    {:ok, restored_state} = AgentServer.state(restored_pid)
    assert restored_state.children.nested.pid == nested_pid

    {:ok, nested_state} = AgentServer.state(nested_pid)
    assert nested_state.children.planner.pid == nested_planner_pid
  end

  test "nested pod nodes fail fast when the manager is configured for a different pod module",
       %{jido: jido} do
    storage_table = :"pod_runtime_manager_mismatch_storage_#{System.unique_integer([:positive])}"
    manager = :"pod_runtime_manager_mismatch_manager_#{System.unique_integer([:positive])}"

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: manager,
          agent: ManagerMismatchPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    assert {:error, %{stage: :reconcile, pod: pid, reason: report}} =
             Pod.get(manager, "group-123")

    assert Process.alive?(pid)
    assert report.failed == [:nested]

    assert inspect(report.failures.nested) =~
             "requires the nested pod manager to manage the declared pod module"
  end

  test "reconcile reports partial success when one eager node cannot run", %{jido: jido} do
    storage_table = :"pod_runtime_partial_storage_#{System.unique_integer([:positive])}"
    manager = :"pod_runtime_partial_pod_manager_#{System.unique_integer([:positive])}"

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: manager,
          agent: PartialFailurePod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    assert {:error, %{stage: :reconcile, pod: pod_pid, reason: report}} =
             Pod.get(manager, "partial-123")

    assert Process.alive?(pod_pid)
    assert report.completed == [:planner]
    assert report.failed == [:nested]
    assert report.pending == []
    assert Map.has_key?(report.nodes, :planner)
    assert report.failures.nested.stage == :nested_reconcile
    assert inspect(report.failures.nested.reason) =~ "Recursive pod runtime is not supported"
  end
end
