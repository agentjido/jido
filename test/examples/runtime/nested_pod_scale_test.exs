defmodule JidoExampleTest.NestedPodScaleTest do
  @moduledoc """
  Example test demonstrating a hierarchy of nested pods at load.

  This example pushes on the current hierarchical pod runtime using a real
  pod-of-pods shape:

  - one durable root pod manager
  - one root coordinator agent
  - 10 eager nested pod managers adopted under that coordinator
  - each nested pod eagerly reconciles 100 worker nodes in its own hierarchy

  Total runtime members after boot:

  - 1 root pod manager
  - 1 coordinator agent
  - 10 nested pod managers
  - 1000 worker agents inside nested pods

  This is the current scalable hierarchy story: nested pod managers are durable
  runtime nodes, but each pod still owns and reconciles its own topology.

  ## Run

      mix test --include example test/examples/runtime/nested_pod_scale_test.exs
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 120_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Storage.ETS

  @worker_manager :example_nested_scale_workers
  @child_pod_manager :example_nested_scale_child_pods
  @root_pod_manager :example_nested_scale_root_pods

  defmodule ScaleWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "example_nested_scale_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule GroupTopologyBuilder do
    @moduledoc false

    @lead_count 10
    @workers_per_lead 9

    def topology do
      Jido.Pod.Topology.new!(
        name: "nested_scale_group_pod",
        nodes: nodes(),
        links: links()
      )
    end

    def total_nodes do
      @lead_count + @lead_count * @workers_per_lead
    end

    def sample_nodes do
      [:lead_1, :lead_10, :worker_1_1, :worker_10_9]
    end

    defp nodes do
      lead_nodes()
      |> Map.merge(worker_nodes())
    end

    defp lead_nodes do
      Map.new(1..@lead_count, fn lead_index ->
        name = lead_name(lead_index)

        {name,
         %{
           agent: JidoExampleTest.NestedPodScaleTest.ScaleWorkerAgent,
           manager: :example_nested_scale_workers,
           activation: :eager,
           initial_state: %{role: Atom.to_string(name)}
         }}
      end)
    end

    defp worker_nodes do
      Map.new(
        for lead_index <- 1..@lead_count, worker_index <- 1..@workers_per_lead do
          name = worker_name(lead_index, worker_index)

          {name,
           %{
             agent: JidoExampleTest.NestedPodScaleTest.ScaleWorkerAgent,
             manager: :example_nested_scale_workers,
             activation: :eager,
             initial_state: %{role: Atom.to_string(name)}
           }}
        end
      )
    end

    defp links do
      for lead_index <- 1..@lead_count,
          worker_index <- 1..@workers_per_lead,
          link <- [
            {:owns, lead_name(lead_index), worker_name(lead_index, worker_index)},
            {:depends_on, worker_name(lead_index, worker_index), lead_name(lead_index)}
          ] do
        link
      end
    end

    defp lead_name(index), do: String.to_atom("lead_#{index}")

    defp worker_name(lead_index, worker_index),
      do: String.to_atom("worker_#{lead_index}_#{worker_index}")
  end

  defmodule WorkerGroupPod do
    @moduledoc false
    use Jido.Pod,
      name: "worker_group_pod",
      topology: JidoExampleTest.NestedPodScaleTest.GroupTopologyBuilder.topology()
  end

  defmodule RootTopologyBuilder do
    @moduledoc false

    @group_count 10

    def topology do
      Jido.Pod.Topology.new!(
        name: "nested_scale_root_pod",
        nodes: nodes(),
        links: links()
      )
    end

    def total_nodes, do: 1 + @group_count

    def sample_groups do
      [:group_1, :group_5, :group_10]
    end

    defp nodes do
      coordinator_node()
      |> Map.merge(group_nodes())
    end

    defp coordinator_node do
      %{
        coordinator: %{
          agent: JidoExampleTest.NestedPodScaleTest.ScaleWorkerAgent,
          manager: :example_nested_scale_workers,
          activation: :eager,
          initial_state: %{role: "coordinator"}
        }
      }
    end

    defp group_nodes do
      Map.new(1..@group_count, fn index ->
        {group_name(index),
         %{
           module: JidoExampleTest.NestedPodScaleTest.WorkerGroupPod,
           manager: :example_nested_scale_child_pods,
           kind: :pod,
           activation: :eager
         }}
      end)
    end

    defp links do
      Enum.map(1..@group_count, fn index ->
        {:owns, :coordinator, group_name(index)}
      end)
    end

    defp group_name(index), do: String.to_atom("group_#{index}")
  end

  defmodule RootHierarchyPod do
    @moduledoc false
    use Jido.Pod,
      name: "root_hierarchy_pod",
      topology: JidoExampleTest.NestedPodScaleTest.RootTopologyBuilder.topology()
  end

  setup %{jido: jido} do
    storage_table = :"example_nested_scale_storage_#{System.unique_integer([:positive])}"

    {:ok, _worker_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @worker_manager,
          agent: ScaleWorkerAgent,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _child_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @child_pod_manager,
          agent: WorkerGroupPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _root_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @root_pod_manager,
          agent: RootHierarchyPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @worker_manager})
      :persistent_term.erase({InstanceManager, @child_pod_manager})
      :persistent_term.erase({InstanceManager, @root_pod_manager})
    end)

    {:ok, pod_key: "nested-scale-123"}
  end

  describe "nested pod hierarchy at load" do
    test "loads 10 nested pod managers and 1000 inner workers", %{pod_key: pod_key} do
      assert {:ok, root_pid} = Pod.get(@root_pod_manager, pod_key)

      assert {:ok, %Pod.Topology{} = topology} = Pod.fetch_topology(root_pid)
      assert map_size(topology.nodes) == RootTopologyBuilder.total_nodes()

      assert InstanceManager.stats(@root_pod_manager).count == 1
      assert InstanceManager.stats(@child_pod_manager).count == 10
      assert InstanceManager.stats(@worker_manager).count == 1001

      assert {:ok, root_snapshots} = Pod.nodes(root_pid)
      assert map_size(root_snapshots) == RootTopologyBuilder.total_nodes()
      assert adopted_count(root_snapshots) == RootTopologyBuilder.total_nodes()

      assert {:ok, coordinator_pid} = Pod.lookup_node(root_pid, :coordinator)
      {:ok, coordinator_state} = AgentServer.state(coordinator_pid)

      Enum.each(RootTopologyBuilder.sample_groups(), fn group_name ->
        assert {:ok, group_pid} = Pod.lookup_node(root_pid, group_name)
        assert coordinator_state.children[group_name].pid == group_pid

        assert {:ok, group_snapshots} = Pod.nodes(group_pid)
        assert map_size(group_snapshots) == GroupTopologyBuilder.total_nodes()
        assert adopted_count(group_snapshots) == GroupTopologyBuilder.total_nodes()

        Enum.each(GroupTopologyBuilder.sample_nodes(), fn node_name ->
          assert {:ok, pid} = Pod.lookup_node(group_pid, node_name)
          assert Process.alive?(pid)
          assert group_snapshots[node_name].status == :adopted
        end)
      end)

      assert {:ok, group_pid} = Pod.lookup_node(root_pid, :group_1)
      assert {:ok, lead_pid} = Pod.lookup_node(group_pid, :lead_1)
      assert {:ok, worker_pid} = Pod.lookup_node(group_pid, :worker_1_1)

      {:ok, lead_state} = AgentServer.state(lead_pid)
      assert lead_state.children.worker_1_1.pid == worker_pid
    end

    test "thaw restores the root boundary while nested pod managers keep their inner ownership",
         %{
           pod_key: pod_key
         } do
      assert {:ok, root_pid} = Pod.get(@root_pod_manager, pod_key)
      assert {:ok, coordinator_pid} = Pod.lookup_node(root_pid, :coordinator)
      assert {:ok, group_1_pid} = Pod.lookup_node(root_pid, :group_1)
      assert {:ok, group_10_pid} = Pod.lookup_node(root_pid, :group_10)
      assert {:ok, lead_pid} = Pod.lookup_node(group_1_pid, :lead_1)
      assert {:ok, worker_pid} = Pod.lookup_node(group_1_pid, :worker_1_1)

      root_ref = Process.monitor(root_pid)
      assert :ok = InstanceManager.stop(@root_pod_manager, pod_key)
      assert_receive {:DOWN, ^root_ref, :process, ^root_pid, _reason}, 5_000

      assert Process.alive?(coordinator_pid)
      assert Process.alive?(group_1_pid)
      assert Process.alive?(group_10_pid)
      assert Process.alive?(lead_pid)
      assert Process.alive?(worker_pid)

      {:ok, coordinator_state} = AgentServer.state(coordinator_pid)
      assert coordinator_state.parent == nil
      assert coordinator_state.orphaned_from.id == pod_key

      {:ok, group_state} = AgentServer.state(group_1_pid)
      assert group_state.parent.pid == coordinator_pid

      {:ok, worker_state} = AgentServer.state(worker_pid)
      assert worker_state.parent.pid == lead_pid

      assert {:ok, restored_root_pid} = Pod.get(@root_pod_manager, pod_key)
      assert restored_root_pid != root_pid
      assert {:ok, ^coordinator_pid} = Pod.lookup_node(restored_root_pid, :coordinator)
      assert {:ok, ^group_1_pid} = Pod.lookup_node(restored_root_pid, :group_1)
      assert {:ok, ^group_10_pid} = Pod.lookup_node(restored_root_pid, :group_10)

      assert InstanceManager.stats(@root_pod_manager).count == 1
      assert InstanceManager.stats(@child_pod_manager).count == 10
      assert InstanceManager.stats(@worker_manager).count == 1001

      assert {:ok, root_snapshots} = Pod.nodes(restored_root_pid)
      assert adopted_count(root_snapshots) == RootTopologyBuilder.total_nodes()

      assert {:ok, group_snapshots} = Pod.nodes(group_1_pid)
      assert adopted_count(group_snapshots) == GroupTopologyBuilder.total_nodes()

      {:ok, restored_coordinator_state} = AgentServer.state(coordinator_pid)
      assert restored_coordinator_state.children.group_1.pid == group_1_pid
    end
  end

  defp adopted_count(snapshots) do
    Enum.count(snapshots, fn {_name, snapshot} -> snapshot.status == :adopted end)
  end
end
