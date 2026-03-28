defmodule JidoExampleTest.PartitionedPodRuntimeTest do
  @moduledoc """
  Example test demonstrating Pod-first logical multi-tenancy.

  This example keeps the runtime single-instance, but treats `partition` as the
  tenant/workspace boundary and `Jido.Pod` as the durable unit inside that
  boundary.

  It proves:

  - the same pod key can exist in multiple partitions
  - eager and lazy members stay isolated by partition
  - nested node lookups and runtime lineage preserve the tenant boundary

  ## Run

      mix test --include example test/examples/runtime/partitioned_pod_runtime_test.exs
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 30_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Pod.Topology
  alias Jido.Storage.ETS

  @worker_manager :example_partitioned_pod_workers
  @pod_manager :example_partitioned_pod_manager

  defmodule TenantWorker do
    @moduledoc false
    use Jido.Agent,
      name: "example_partitioned_tenant_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule WorkspacePod do
    @moduledoc false
    use Jido.Pod,
      name: "workspace_pod",
      topology:
        Topology.new!(
          name: "workspace_pod",
          nodes: %{
            coordinator: %{
              agent: TenantWorker,
              manager: :example_partitioned_pod_workers,
              activation: :eager,
              initial_state: %{role: "coordinator"}
            },
            reviewer: %{
              agent: TenantWorker,
              manager: :example_partitioned_pod_workers,
              activation: :lazy,
              initial_state: %{role: "reviewer"}
            }
          },
          links: [{:owns, :coordinator, :reviewer}]
        )
  end

  setup %{jido: jido} do
    storage_table = :"example_partitioned_pod_storage_#{System.unique_integer([:positive])}"

    {:ok, _worker_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @worker_manager,
          agent: TenantWorker,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @pod_manager,
          agent: WorkspacePod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @worker_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "workspace-123"}
  end

  test "the same workspace pod key can exist across partitions without collisions", %{
    pod_key: pod_key
  } do
    coordinator_key = {WorkspacePod, pod_key, :coordinator}
    reviewer_key = {WorkspacePod, pod_key, :reviewer}

    assert {:ok, alpha_pod_pid} = Pod.get(@pod_manager, pod_key, partition: :alpha)
    assert {:ok, beta_pod_pid} = Pod.get(@pod_manager, pod_key, partition: :beta)
    refute alpha_pod_pid == beta_pod_pid

    assert {:ok, alpha_coordinator_pid} = Pod.lookup_node(alpha_pod_pid, :coordinator)
    assert {:ok, beta_coordinator_pid} = Pod.lookup_node(beta_pod_pid, :coordinator)
    refute alpha_coordinator_pid == beta_coordinator_pid

    assert {:ok, ^alpha_coordinator_pid} =
             InstanceManager.lookup(@worker_manager, coordinator_key, partition: :alpha)

    assert {:ok, ^beta_coordinator_pid} =
             InstanceManager.lookup(@worker_manager, coordinator_key, partition: :beta)

    assert :error = Pod.lookup_node(alpha_pod_pid, :reviewer)
    assert :error = Pod.lookup_node(beta_pod_pid, :reviewer)

    assert {:ok, alpha_reviewer_pid} = Pod.ensure_node(alpha_pod_pid, :reviewer)
    assert {:ok, ^alpha_reviewer_pid} = Pod.lookup_node(alpha_pod_pid, :reviewer)
    assert :error = Pod.lookup_node(beta_pod_pid, :reviewer)

    assert {:ok, ^alpha_reviewer_pid} =
             InstanceManager.lookup(@worker_manager, reviewer_key, partition: :alpha)

    assert InstanceManager.lookup(@worker_manager, reviewer_key, partition: :beta) == :error

    {:ok, alpha_coordinator_state} = AgentServer.state(alpha_coordinator_pid)
    {:ok, beta_coordinator_state} = AgentServer.state(beta_coordinator_pid)
    assert alpha_coordinator_state.partition == :alpha
    assert alpha_coordinator_state.parent.partition == :alpha
    assert beta_coordinator_state.partition == :beta
    assert beta_coordinator_state.parent.partition == :beta
  end
end
