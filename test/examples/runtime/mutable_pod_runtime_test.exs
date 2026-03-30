defmodule JidoExampleTest.MutablePodRuntimeTest do
  @moduledoc """
  Example test demonstrating the simplest mutable `Jido.Pod` story.

  This example focuses on the happy path:

  - start with an empty durable pod
  - add eager and lazy members with `Jido.Pod.mutate/3`
  - activate a lazy member with `Jido.Pod.ensure_node/3`
  - reacquire the pod later with the same durable topology

  ## Run

      mix test --include example test/examples/runtime/mutable_pod_runtime_test.exs
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 30_000

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Pod.Mutation
  alias Jido.Storage.ETS

  @worker_manager :example_mutable_pod_workers
  @pod_manager :example_mutable_review_pods

  defmodule ReviewWorkerAgent do
    @moduledoc false
    use Jido.Agent,
      name: "example_mutable_pod_review_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule MutableReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "example_mutable_review_pod"
  end

  setup %{jido: jido} do
    storage_table = :"example_mutable_pod_storage_#{System.unique_integer([:positive])}"

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
          agent: MutableReviewPod,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @worker_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "review-123"}
  end

  test "a pod can grow durably over time", %{pod_key: pod_key} do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert {:ok, topology} = Pod.fetch_topology(pod_pid)
    assert topology.nodes == %{}

    assert {:ok, report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("planner", %{
                   agent: ReviewWorkerAgent,
                   manager: @worker_manager,
                   activation: :eager,
                   initial_state: %{role: "planner"}
                 }),
                 Mutation.add_node(
                   "reviewer",
                   %{
                     agent: ReviewWorkerAgent,
                     manager: @worker_manager,
                     activation: :lazy,
                     initial_state: %{role: "reviewer"}
                   },
                   owner: "planner",
                   depends_on: ["planner"]
                 )
               ]
             )

    assert report.status == :completed
    assert report.added == ["planner", "reviewer"]
    assert report.started == ["planner"]

    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, "planner")
    assert :error = Pod.lookup_node(pod_pid, "reviewer")
    assert {:ok, reviewer_pid} = Pod.ensure_node(pod_pid, "reviewer")

    assert {:ok, planner_state} = AgentServer.state(planner_pid)
    assert planner_state.children["reviewer"].pid == reviewer_pid

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(@pod_manager, pod_key)
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000

    assert Process.alive?(planner_pid)
    assert Process.alive?(reviewer_pid)

    assert {:ok, restored_pid} = Pod.get(@pod_manager, pod_key)
    refute restored_pid == pod_pid

    assert {:ok, restored_topology} = Pod.fetch_topology(restored_pid)
    assert restored_topology.nodes |> Map.keys() |> Enum.sort() == ["planner", "reviewer"]
    assert {:ok, ^planner_pid} = Pod.lookup_node(restored_pid, "planner")
    assert {:ok, ^reviewer_pid} = Pod.ensure_node(restored_pid, "reviewer")
  end
end
