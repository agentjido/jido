defmodule JidoExampleTest.PodRuntimeTest do
  @moduledoc """
  Example tests demonstrating the current `Jido.Pod` runtime contract.

  This file has two goals:

  - show the normal happy path for a manager-led durable pod
  - aggressively exercise the thaw and reattachment boundary to prove what pods
    do and do not persist

  ## What This Covers

  - `use Jido.Pod` wraps an ordinary agent module
  - `Jido.Pod.get/3` is the happy path over `InstanceManager.get/3`
  - eager nodes start in `:depends_on` order during reconcile
  - lazy nodes are materialized on demand with `ensure_node/3`
  - pod topology persists, but live attachments do not
  - surviving nodes can be re-adopted after the pod manager thaws
  - lazy survivors remain `:running` until explicitly re-adopted

  ## Run

      mix test --include example test/examples/runtime/pod_runtime_test.exs

  ## Important Boundary

  Pods are still a flat, manager-led runtime. Hierarchy can be described in
  topology data, but this example only exercises supported `kind: :agent`
  nodes.
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 30_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Storage.ETS

  @worker_manager :example_pod_runtime_workers
  @pod_manager :example_pod_runtime_manager

  defmodule ReviewWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "example_pod_review_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule ReviewPipelinePod do
    @moduledoc false
    use Jido.Pod,
      name: "review_pipeline",
      topology:
        Jido.Pod.Topology.new!(
          name: "review_pipeline",
          nodes: %{
            planner: %{
              agent: ReviewWorkerAgent,
              manager: :example_pod_runtime_workers,
              activation: :eager,
              initial_state: %{role: "planner"}
            },
            reviewer: %{
              agent: ReviewWorkerAgent,
              manager: :example_pod_runtime_workers,
              activation: :eager,
              initial_state: %{role: "reviewer"}
            },
            publisher: %{
              agent: ReviewWorkerAgent,
              manager: :example_pod_runtime_workers,
              activation: :eager,
              initial_state: %{role: "publisher"}
            },
            auditor: %{
              agent: ReviewWorkerAgent,
              manager: :example_pod_runtime_workers,
              activation: :lazy,
              initial_state: %{role: "auditor"}
            }
          },
          links: [
            {:depends_on, :reviewer, :planner},
            {:depends_on, :publisher, :reviewer}
          ]
        )
  end

  setup %{jido: jido} do
    test_pid = self()
    handler_id = "example-pod-runtime-telemetry-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :pod, :reconcile, :start],
        [:jido, :pod, :reconcile, :stop],
        [:jido, :pod, :node, :ensure, :start],
        [:jido, :pod, :node, :ensure, :stop]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    storage_table = :"example_pod_runtime_storage_#{System.unique_integer([:positive])}"

    {:ok, _worker_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @worker_manager,
          agent: ReviewWorkerAgent,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    {:ok, _pod_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @pod_manager,
          agent: ReviewPipelinePod,
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

    {:ok, pod_key: "review-123"}
  end

  describe "basic pod usage" do
    test "Pod.get starts eager nodes and ensure_node activates lazy nodes", %{pod_key: pod_key} do
      assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)

      assert {:ok, %Pod.Topology{name: "review_pipeline"} = topology} =
               Pod.fetch_topology(pod_pid)

      assert topology.nodes |> Map.keys() |> Enum.sort() == [:auditor, :planner, :publisher, :reviewer]

      assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)
      assert {:ok, reviewer_pid} = Pod.lookup_node(pod_pid, :reviewer)
      assert {:ok, publisher_pid} = Pod.lookup_node(pod_pid, :publisher)
      assert :error = Pod.lookup_node(pod_pid, :auditor)

      assert {:ok, snapshots} = Pod.nodes(pod_pid)
      assert snapshots.planner.status == :adopted
      assert snapshots.reviewer.status == :adopted
      assert snapshots.publisher.status == :adopted
      assert snapshots.auditor.status == :stopped

      assert {:ok, auditor_pid} = Pod.ensure_node(pod_pid, :auditor)
      assert {:ok, ^auditor_pid} = Pod.lookup_node(pod_pid, :auditor)

      assert {:ok, snapshots} = Pod.nodes(pod_pid)
      assert snapshots.auditor.status == :adopted

      assert Process.alive?(planner_pid)
      assert Process.alive?(reviewer_pid)
      assert Process.alive?(publisher_pid)
      assert Process.alive?(auditor_pid)
    end
  end

  describe "aggressive durability path" do
    test "surviving nodes reattach after thaw in dependency order and lazy survivors stay explicit",
         %{pod_key: pod_key} do
      assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
      assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)
      assert {:ok, reviewer_pid} = Pod.lookup_node(pod_pid, :reviewer)
      assert {:ok, publisher_pid} = Pod.lookup_node(pod_pid, :publisher)
      assert {:ok, auditor_pid} = Pod.ensure_node(pod_pid, :auditor)

      drain_telemetry_events()

      pod_ref = Process.monitor(pod_pid)
      assert :ok = InstanceManager.stop(@pod_manager, pod_key)
      assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

      assert Process.alive?(planner_pid)
      assert Process.alive?(reviewer_pid)
      assert Process.alive?(publisher_pid)
      assert Process.alive?(auditor_pid)

      assert {:ok, planner_state} = AgentServer.state(planner_pid)
      assert planner_state.parent == nil
      assert planner_state.orphaned_from.id == pod_key

      assert {:ok, auditor_state} = AgentServer.state(auditor_pid)
      assert auditor_state.parent == nil
      assert auditor_state.orphaned_from.id == pod_key

      assert {:ok, restored_pid} = Pod.get(@pod_manager, pod_key)
      assert restored_pid != pod_pid

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :start], %{system_time: _},
                      %{pod_id: ^pod_key, pod_module: ReviewPipelinePod}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                      %{node_name: :planner, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                      %{node_name: :planner, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                      %{node_name: :reviewer, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                      %{node_name: :reviewer, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                      %{node_name: :publisher, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                      %{node_name: :publisher, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :stop],
                      %{duration: _, node_count: 3},
                      %{pod_id: ^pod_key, pod_module: ReviewPipelinePod}}

      assert {:ok, ^planner_pid} = Pod.lookup_node(restored_pid, :planner)
      assert {:ok, ^reviewer_pid} = Pod.lookup_node(restored_pid, :reviewer)
      assert {:ok, ^publisher_pid} = Pod.lookup_node(restored_pid, :publisher)

      assert {:ok, snapshots} = Pod.nodes(restored_pid)
      assert snapshots.planner.status == :adopted
      assert snapshots.reviewer.status == :adopted
      assert snapshots.publisher.status == :adopted
      assert snapshots.auditor.status == :running
      assert snapshots.auditor.adopted_pid == nil
      assert snapshots.auditor.running_pid == auditor_pid

      assert {:ok, ^auditor_pid} = Pod.ensure_node(restored_pid, :auditor)

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                      %{node_name: :auditor, source: :running}}

      assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                      %{node_name: :auditor, source: :running}}

      assert {:ok, snapshots} = Pod.nodes(restored_pid)
      assert snapshots.auditor.status == :adopted
      assert snapshots.auditor.adopted_pid == auditor_pid
    end
  end

  defp drain_telemetry_events do
    receive do
      {:telemetry_event, _event, _measurements, _metadata} ->
        drain_telemetry_events()
    after
      0 -> :ok
    end
  end
end
