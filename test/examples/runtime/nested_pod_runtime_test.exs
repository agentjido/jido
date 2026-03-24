defmodule JidoExampleTest.NestedPodRuntimeTest do
  @moduledoc """
  Example test demonstrating nested pod runtime ownership.

  This example focuses on the new `kind: :pod` path:

  - a parent pod owns an ordinary agent root
  - that root owns a nested pod node
  - the nested pod manages its own internal topology
  - thaw repairs the broken outer ownership edge without rebuilding the whole
    nested runtime tree

  ## Run

      mix test --include example test/examples/runtime/nested_pod_runtime_test.exs
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 45_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Storage.ETS

  @worker_manager :example_nested_pod_workers
  @child_pod_manager :example_nested_child_pods
  @parent_pod_manager :example_nested_parent_pods

  defmodule WorkflowWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "example_nested_pod_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule EditorialPod do
    @moduledoc false
    use Jido.Pod,
      name: "editorial_pod",
      topology:
        Jido.Pod.Topology.new!(
          name: "editorial_pod",
          nodes: %{
            editor: %{
              agent: WorkflowWorkerAgent,
              manager: :example_nested_pod_workers,
              activation: :eager,
              initial_state: %{role: "editor"}
            },
            publisher: %{
              agent: WorkflowWorkerAgent,
              manager: :example_nested_pod_workers,
              activation: :lazy,
              initial_state: %{role: "publisher"}
            }
          },
          links: [{:owns, :editor, :publisher}]
        )
  end

  defmodule ProgramPod do
    @moduledoc false
    use Jido.Pod,
      name: "program_pod",
      topology:
        Jido.Pod.Topology.new!(
          name: "program_pod",
          nodes: %{
            coordinator: %{
              agent: WorkflowWorkerAgent,
              manager: :example_nested_pod_workers,
              activation: :eager,
              initial_state: %{role: "coordinator"}
            },
            editorial: %{
              module: EditorialPod,
              manager: :example_nested_child_pods,
              kind: :pod,
              activation: :eager
            },
            auditor: %{
              agent: WorkflowWorkerAgent,
              manager: :example_nested_pod_workers,
              activation: :lazy,
              initial_state: %{role: "auditor"}
            }
          },
          links: [
            {:owns, :coordinator, :editorial}
          ]
        )
  end

  setup %{jido: jido} do
    storage_table = :"example_nested_pod_storage_#{System.unique_integer([:positive])}"

    {:ok, _worker_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @worker_manager,
          agent: WorkflowWorkerAgent,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _child_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @child_pod_manager,
          agent: EditorialPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _parent_pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @parent_pod_manager,
          agent: ProgramPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @worker_manager})
      :persistent_term.erase({InstanceManager, @child_pod_manager})
      :persistent_term.erase({InstanceManager, @parent_pod_manager})
    end)

    {:ok, pod_key: "program-123"}
  end

  test "nested pod nodes attach under their runtime owner and manage their own topology", %{
    pod_key: pod_key
  } do
    assert {:ok, parent_pid} = Pod.get(@parent_pod_manager, pod_key)

    parent_nested_key = {ProgramPod, pod_key, :editorial}
    nested_editor_key = {EditorialPod, parent_nested_key, :editor}
    nested_publisher_key = {EditorialPod, parent_nested_key, :publisher}

    assert {:ok, coordinator_pid} = Pod.lookup_node(parent_pid, :coordinator)
    assert {:ok, nested_pid} = Pod.lookup_node(parent_pid, :editorial)
    assert {:ok, ^nested_pid} = InstanceManager.lookup(@child_pod_manager, parent_nested_key)

    {:ok, parent_state} = AgentServer.state(parent_pid)
    assert parent_state.children.coordinator.pid == coordinator_pid
    refute Map.has_key?(parent_state.children, :editorial)

    {:ok, coordinator_state} = AgentServer.state(coordinator_pid)
    assert coordinator_state.children.editorial.pid == nested_pid

    assert {:ok, editor_pid} = Pod.lookup_node(nested_pid, :editor)
    assert {:ok, ^editor_pid} = InstanceManager.lookup(@worker_manager, nested_editor_key)
    assert :error = Pod.lookup_node(nested_pid, :publisher)
    assert :error = InstanceManager.lookup(@worker_manager, nested_publisher_key)

    assert {:ok, publisher_pid} = Pod.ensure_node(nested_pid, :publisher)
    assert {:ok, ^publisher_pid} = Pod.lookup_node(nested_pid, :publisher)
    assert {:ok, ^publisher_pid} = InstanceManager.lookup(@worker_manager, nested_publisher_key)
  end

  test "thaw repairs the outer boundary while the nested pod keeps its internal ownership", %{
    pod_key: pod_key
  } do
    assert {:ok, parent_pid} = Pod.get(@parent_pod_manager, pod_key)
    assert {:ok, coordinator_pid} = Pod.lookup_node(parent_pid, :coordinator)
    assert {:ok, nested_pid} = Pod.lookup_node(parent_pid, :editorial)
    assert {:ok, editor_pid} = Pod.lookup_node(nested_pid, :editor)

    parent_ref = Process.monitor(parent_pid)
    assert :ok = InstanceManager.stop(@parent_pod_manager, pod_key)
    assert_receive {:DOWN, ^parent_ref, :process, ^parent_pid, _reason}, 1_000

    assert Process.alive?(coordinator_pid)
    assert Process.alive?(nested_pid)
    assert Process.alive?(editor_pid)

    {:ok, coordinator_state} = AgentServer.state(coordinator_pid)
    assert coordinator_state.parent == nil
    assert coordinator_state.orphaned_from.id == pod_key

    {:ok, nested_state} = AgentServer.state(nested_pid)
    assert nested_state.parent.pid == coordinator_pid

    {:ok, editor_state} = AgentServer.state(editor_pid)
    assert editor_state.parent.pid == nested_pid

    assert {:ok, restored_pid} = Pod.get(@parent_pod_manager, pod_key)
    assert restored_pid != parent_pid
    assert {:ok, ^nested_pid} = Pod.lookup_node(restored_pid, :editorial)

    {:ok, restored_parent_state} = AgentServer.state(restored_pid)
    assert restored_parent_state.children.coordinator.pid == coordinator_pid

    {:ok, restored_nested_state} = AgentServer.state(nested_pid)
    assert restored_nested_state.children.editor.pid == editor_pid
  end
end
