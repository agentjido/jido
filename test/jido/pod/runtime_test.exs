defmodule JidoTest.Pod.RuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Storage.ETS

  @planner_manager :pod_runtime_planner_members
  @reviewer_manager :pod_runtime_reviewer_members
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
      topology: %{
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

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @planner_manager})
      :persistent_term.erase({InstanceManager, @reviewer_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "order-123"}
  end

  test "reconcile eagerly starts eager nodes and ensure_node lazily activates others", %{
    pod_key: pod_key
  } do
    assert {:ok, pod_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert {:ok, %Pod.Topology{name: "runtime_review_pod"}} = Pod.fetch_topology(pod_pid)

    assert {:ok, started} = Pod.reconcile(pod_pid)
    assert Map.has_key?(started, :planner)

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
    assert manager_state.children.reviewer.pid == reviewer_pid
  end

  test "restored pod managers can re-adopt surviving eager nodes", %{pod_key: pod_key} do
    assert {:ok, pod_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert {:ok, _started} = Pod.reconcile(pod_pid)
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(@pod_manager, pod_key)
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

    assert Process.alive?(planner_pid)
    assert {:ok, planner_state} = AgentServer.state(planner_pid)
    assert planner_state.parent == nil
    assert planner_state.orphaned_from.id == pod_key

    assert {:ok, restored_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert restored_pid != pod_pid
    assert {:ok, _started} = Pod.reconcile(restored_pid)
    assert {:ok, ^planner_pid} = Pod.lookup_node(restored_pid, :planner)

    planner_key = {ReviewPod, pod_key, :planner}
    assert {:ok, ^planner_pid} = InstanceManager.lookup(@planner_manager, planner_key)
  end

  test "thaw restores pod topology immediately and stages lazy node re-adoption explicitly", %{
    pod_key: pod_key
  } do
    assert {:ok, pod_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert {:ok, _started} = Pod.reconcile(pod_pid)
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
    assert snapshots.reviewer.status == :running
    assert snapshots.reviewer.running_pid == reviewer_pid
    assert snapshots.reviewer.adopted_pid == nil

    assert {:ok, _started} = Pod.reconcile(restored_pid)
    assert {:ok, snapshots} = Pod.nodes(restored_pid)
    assert snapshots.planner.status == :adopted
    assert snapshots.planner.adopted_pid == planner_pid
    assert snapshots.reviewer.status == :running
    assert snapshots.reviewer.adopted_pid == nil

    assert {:ok, ^reviewer_pid} = Pod.ensure_node(restored_pid, :reviewer)
    assert {:ok, snapshots} = Pod.nodes(restored_pid)
    assert snapshots.reviewer.status == :adopted
    assert snapshots.reviewer.adopted_pid == reviewer_pid
  end
end
