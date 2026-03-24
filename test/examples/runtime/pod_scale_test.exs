defmodule JidoExampleTest.PodScaleTest do
  @moduledoc """
  Example test demonstrating a hierarchy-shaped pod at load.

  This example is intentionally large. It treats a 1000-node pod as a standard
  use case and pushes on the current runtime contract:

  - the topology encodes hierarchy-like structure with `:owns` and `:depends_on`
  - runtime semantics remain flat and manager-led
  - all nodes are durable `kind: :agent` members
  - eager reconciliation must handle the full topology
  - thaw must re-adopt surviving members at scale

  ## Topology Shape

  - 10 lead nodes
  - 90 squad nodes (9 per lead)
  - 900 worker nodes (10 per squad)

  Total: 1000 pod-managed nodes

  ## Run

      mix test --include example test/examples/runtime/pod_scale_test.exs

  ## Important Boundary

  This is a hierarchy-shaped topology, not a recursive pod runtime. The current
  `Jido.Pod` implementation still has one durable pod manager that owns all live
  members directly.
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 90_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Storage.ETS

  @worker_manager :example_pod_scale_workers
  @pod_manager :example_pod_scale_pods

  defmodule ScaleWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "example_pod_scale_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule TopologyBuilder do
    @moduledoc false

    @lead_count 10
    @squads_per_lead 9
    @workers_per_squad 10

    def topology do
      Jido.Pod.Topology.new!(
        name: "hierarchy_shaped_scale_pod",
        nodes: nodes(),
        links: links()
      )
    end

    def total_nodes do
      @lead_count + @lead_count * @squads_per_lead +
        @lead_count * @squads_per_lead * @workers_per_squad
    end

    def total_links do
      @lead_count * @squads_per_lead * 2 +
        @lead_count * @squads_per_lead * @workers_per_squad * 2
    end

    def sample_nodes do
      [:lead_1, :lead_10, :squad_1_1, :squad_10_9, :worker_1_1_1, :worker_10_9_10]
    end

    defp nodes do
      lead_nodes()
      |> Map.merge(squad_nodes())
      |> Map.merge(worker_nodes())
    end

    defp lead_nodes do
      Map.new(1..@lead_count, fn lead_index ->
        name = lead_name(lead_index)

        {name,
         %{
           agent: JidoExampleTest.PodScaleTest.ScaleWorkerAgent,
           manager: :example_pod_scale_workers,
           activation: :eager,
           initial_state: %{role: Atom.to_string(name)}
         }}
      end)
    end

    defp squad_nodes do
      Map.new(
        for lead_index <- 1..@lead_count, squad_index <- 1..@squads_per_lead do
          name = squad_name(lead_index, squad_index)

          {name,
           %{
             agent: JidoExampleTest.PodScaleTest.ScaleWorkerAgent,
             manager: :example_pod_scale_workers,
             activation: :eager,
             initial_state: %{role: Atom.to_string(name)}
           }}
        end
      )
    end

    defp worker_nodes do
      Map.new(
        for lead_index <- 1..@lead_count,
            squad_index <- 1..@squads_per_lead,
            worker_index <- 1..@workers_per_squad do
          name = worker_name(lead_index, squad_index, worker_index)

          {name,
           %{
             agent: JidoExampleTest.PodScaleTest.ScaleWorkerAgent,
             manager: :example_pod_scale_workers,
             activation: :eager,
             initial_state: %{role: Atom.to_string(name)}
           }}
        end
      )
    end

    defp links do
      squad_links =
        for lead_index <- 1..@lead_count,
            squad_index <- 1..@squads_per_lead,
            link <- [
              {:owns, lead_name(lead_index), squad_name(lead_index, squad_index)},
              {:depends_on, squad_name(lead_index, squad_index), lead_name(lead_index)}
            ] do
          link
        end

      worker_links =
        for lead_index <- 1..@lead_count,
            squad_index <- 1..@squads_per_lead,
            worker_index <- 1..@workers_per_squad,
            link <- [
              {:owns, squad_name(lead_index, squad_index),
               worker_name(lead_index, squad_index, worker_index)},
              {:depends_on, worker_name(lead_index, squad_index, worker_index),
               squad_name(lead_index, squad_index)}
            ] do
          link
        end

      squad_links ++ worker_links
    end

    defp lead_name(lead_index), do: String.to_atom("lead_#{lead_index}")

    defp squad_name(lead_index, squad_index),
      do: String.to_atom("squad_#{lead_index}_#{squad_index}")

    defp worker_name(lead_index, squad_index, worker_index),
      do: String.to_atom("worker_#{lead_index}_#{squad_index}_#{worker_index}")
  end

  defmodule HierarchyShapedScalePod do
    @moduledoc false
    use Jido.Pod,
      name: "hierarchy_shaped_scale_pod",
      topology: JidoExampleTest.PodScaleTest.TopologyBuilder.topology()
  end

  setup %{jido: jido} do
    test_pid = self()
    handler_id = "example-pod-scale-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :pod, :reconcile, :start],
        [:jido, :pod, :reconcile, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    storage_table = :"example_pod_scale_storage_#{System.unique_integer([:positive])}"

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

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @pod_manager,
          agent: HierarchyShapedScalePod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      :persistent_term.erase({InstanceManager, @worker_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "hierarchy-scale-123"}
  end

  describe "hierarchy-shaped pod load" do
    test "loads and adopts 1000 eager nodes", %{pod_key: pod_key} do
      assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)

      assert {:ok, %Pod.Topology{} = topology} = Pod.fetch_topology(pod_pid)
      assert map_size(topology.nodes) == TopologyBuilder.total_nodes()
      assert length(topology.links) == TopologyBuilder.total_links()

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :start], %{system_time: _},
                      %{pod_id: ^pod_key, pod_module: HierarchyShapedScalePod}}

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :stop],
                      %{duration: duration, node_count: node_count},
                      %{pod_id: ^pod_key, pod_module: HierarchyShapedScalePod}}

      assert duration >= 0
      assert node_count == TopologyBuilder.total_nodes()

      assert {:ok, snapshots} = Pod.nodes(pod_pid)
      assert map_size(snapshots) == TopologyBuilder.total_nodes()
      assert adopted_count(snapshots) == TopologyBuilder.total_nodes()

      Enum.each(TopologyBuilder.sample_nodes(), fn name ->
        assert {:ok, pid} = Pod.lookup_node(pod_pid, name)
        assert Process.alive?(pid)
        assert snapshots[name].status == :adopted
      end)
    end

    test "re-adopts 1000 surviving nodes after manager thaw", %{pod_key: pod_key} do
      assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)

      sample_pids =
        TopologyBuilder.sample_nodes()
        |> Map.new(fn name ->
          {:ok, pid} = Pod.lookup_node(pod_pid, name)
          {name, pid}
        end)

      drain_telemetry_events()

      pod_ref = Process.monitor(pod_pid)
      assert :ok = InstanceManager.stop(@pod_manager, pod_key)
      assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 5_000

      Enum.each(sample_pids, fn {_name, pid} ->
        assert Process.alive?(pid)
        assert {:ok, state} = AgentServer.state(pid)
        assert state.parent == nil
        assert state.orphaned_from.id == pod_key
      end)

      assert {:ok, restored_pid} = Pod.get(@pod_manager, pod_key)
      assert restored_pid != pod_pid

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :start], %{system_time: _},
                      %{pod_id: ^pod_key, pod_module: HierarchyShapedScalePod}}

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :stop],
                      %{duration: duration, node_count: node_count},
                      %{pod_id: ^pod_key, pod_module: HierarchyShapedScalePod}}

      assert duration >= 0
      assert node_count == TopologyBuilder.total_nodes()

      assert {:ok, snapshots} = Pod.nodes(restored_pid)
      assert map_size(snapshots) == TopologyBuilder.total_nodes()
      assert adopted_count(snapshots) == TopologyBuilder.total_nodes()

      Enum.each(sample_pids, fn {name, original_pid} ->
        assert {:ok, ^original_pid} = Pod.lookup_node(restored_pid, name)
        assert snapshots[name].status == :adopted
        assert snapshots[name].adopted_pid == original_pid
      end)
    end
  end

  defp adopted_count(snapshots) do
    Enum.count(snapshots, fn {_name, snapshot} -> snapshot.status == :adopted end)
  end

  defp drain_telemetry_events do
    receive do
      {:telemetry_event, _event, _measurements, _metadata} ->
        drain_telemetry_events()
    after
      0 ->
        :ok
    end
  end
end
