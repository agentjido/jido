defmodule JidoTest.Pod.MutationRuntimeTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.InstanceManager
  alias Jido.AgentServer
  alias Jido.Pod
  alias Jido.Pod.Mutation
  alias Jido.Pod.Topology
  alias Jido.Storage.ETS
  alias Jido.Signal

  @planner_manager :pod_mutation_planner_members
  @reviewer_manager :pod_mutation_reviewer_members
  @nested_pod_manager :pod_mutation_nested_pods
  @slow_manager :pod_mutation_slow_members

  defmodule PodWorker do
    @moduledoc false
    use Jido.Agent,
      name: "pod_mutation_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule SlowMountPlugin do
    @moduledoc false

    use Jido.Plugin,
      name: "slow_mount",
      state_key: :__slow_mount__,
      actions: [],
      schema: Zoi.object(%{}),
      singleton: true

    @impl true
    def mount(_agent, _config) do
      case :persistent_term.get({__MODULE__, :notify_pid}, nil) do
        pid when is_pid(pid) -> send(pid, :slow_mount_started)
        _other -> :ok
      end

      Process.sleep(1_000)
      {:ok, %{}}
    end
  end

  defmodule SlowBootWorker do
    @moduledoc false
    use Jido.Agent,
      name: "pod_mutation_slow_worker",
      schema: [],
      plugins: [SlowMountPlugin]
  end

  defmodule ReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "pod_mutation_review_pod",
      topology:
        Topology.new!(
          name: "pod_mutation_review_pod",
          nodes: %{
            planner: %{
              agent: PodWorker,
              manager: :pod_mutation_planner_members,
              activation: :eager,
              initial_state: %{role: "planner"}
            },
            reviewer: %{
              agent: PodWorker,
              manager: :pod_mutation_reviewer_members,
              activation: :lazy,
              initial_state: %{role: "reviewer"}
            }
          },
          links: [{:owns, :planner, :reviewer}]
        )
  end

  defmodule AlternateReviewPod do
    @moduledoc false
    use Jido.Pod, name: "pod_mutation_alternate_review_pod"
  end

  defmodule EmptyMutablePod do
    @moduledoc false
    use Jido.Pod, name: "pod_mutation_empty_pod"
  end

  defmodule ExpandPodAction do
    @moduledoc false

    alias Jido.Pod
    alias Jido.Pod.Mutation

    use Jido.Action, name: "expand_pod", schema: []

    def run(_params, context) do
      with {:ok, effects} <-
             Pod.mutation_effects(
               context.agent,
               [
                 Mutation.add_node(
                   "planner",
                   %{
                     agent: JidoTest.Pod.MutationRuntimeTest.PodWorker,
                     manager: :pod_mutation_planner_members,
                     activation: :eager,
                     initial_state: %{role: "planner"}
                   }
                 )
               ]
             ) do
        {:ok, %{expanded: true}, effects}
      end
    end
  end

  defmodule SelfMutatingPod do
    @moduledoc false
    use Jido.Pod,
      name: "pod_mutation_self_mutating_pod",
      topology: %{},
      signal_routes: [{"expand", ExpandPodAction}]
  end

  setup %{jido: jido} do
    storage_table = :"pod_mutation_storage_#{System.unique_integer([:positive])}"

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

    {:ok, _slow_manager} =
      start_supervised(
        InstanceManager.child_spec(
          name: @slow_manager,
          agent: SlowBootWorker,
          jido: jido,
          storage: {ETS, table: storage_table},
          agent_opts: [jido: jido, on_parent_death: :continue]
        )
      )

    on_exit(fn ->
      :persistent_term.erase({InstanceManager, @planner_manager})
      :persistent_term.erase({InstanceManager, @reviewer_manager})
      :persistent_term.erase({InstanceManager, @nested_pod_manager})
      :persistent_term.erase({InstanceManager, @slow_manager})
      :persistent_term.erase({SlowMountPlugin, :notify_pid})
    end)

    {:ok, pod_id: unique_id("mutable-pod"), jido: jido}
  end

  test "external mutate adds eager nodes and starts them immediately", %{
    pod_id: pod_id,
    jido: jido
  } do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    assert {:ok, report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node(
                   "planner",
                   %{
                     agent: PodWorker,
                     manager: @planner_manager,
                     activation: :eager,
                     initial_state: %{role: "planner"}
                   }
                 )
               ]
             )

    assert report.status == :completed
    assert report.added == ["planner"]
    assert report.started == ["planner"]

    assert {:ok, topology} = Pod.fetch_topology(pod_pid)
    assert Map.has_key?(topology.nodes, "planner")
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, "planner")
    assert {:ok, planner_state} = AgentServer.state(planner_pid)
    assert planner_state.agent.state.role == "planner"
  end

  test "external mutate persists lazy nodes without starting them", %{pod_id: pod_id, jido: jido} do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    assert {:ok, report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node(
                   "reviewer",
                   %{
                     agent: PodWorker,
                     manager: @reviewer_manager,
                     activation: :lazy,
                     initial_state: %{role: "reviewer"}
                   }
                 )
               ]
             )

    assert report.status == :completed
    assert report.started == []
    assert :error = Pod.lookup_node(pod_pid, "reviewer")
    assert {:ok, topology} = Pod.fetch_topology(pod_pid)
    assert Map.has_key?(topology.nodes, "reviewer")
  end

  test "external mutate adds nested pod nodes and reconciles their eager topology", %{
    pod_id: pod_id,
    jido: jido
  } do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    assert {:ok, report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("nested", %{
                   module: ReviewPod,
                   manager: @nested_pod_manager,
                   kind: :pod,
                   activation: :eager
                 })
               ]
             )

    assert report.status == :completed
    assert {:ok, nested_pid} = Pod.lookup_node(pod_pid, "nested")
    assert {:ok, planner_pid} = Pod.lookup_node(nested_pid, :planner)
    assert Process.alive?(planner_pid)
  end

  test "remove mutations stop leaves and owned subtrees without orphaning descendants", %{
    pod_id: pod_id,
    jido: jido
  } do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    add_ops = [
      Mutation.add_node(
        "planner",
        %{
          agent: PodWorker,
          manager: @planner_manager,
          activation: :eager,
          initial_state: %{role: "planner"}
        }
      ),
      Mutation.add_node(
        "reviewer",
        %{
          agent: PodWorker,
          manager: @reviewer_manager,
          activation: :eager,
          initial_state: %{role: "reviewer"}
        },
        owner: "planner"
      )
    ]

    assert {:ok, _report} = Pod.mutate(pod_pid, add_ops)
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, "planner")
    assert {:ok, reviewer_pid} = Pod.lookup_node(pod_pid, "reviewer")

    assert {:ok, reviewer_report} = Pod.mutate(pod_pid, [Mutation.remove_node("reviewer")])
    assert reviewer_report.status == :completed
    eventually(fn -> not Process.alive?(reviewer_pid) end)
    assert {:error, :unknown_node} = Pod.lookup_node(pod_pid, "reviewer")

    assert {:ok, subtree_report} = Pod.mutate(pod_pid, [Mutation.remove_node("planner")])
    assert subtree_report.status == :completed
    eventually(fn -> not Process.alive?(planner_pid) end)
    refute_eventually(Process.alive?(reviewer_pid))
    assert {:error, :unknown_node} = Pod.lookup_node(pod_pid, "planner")
  end

  test "remove mutations recursively tear down nested pod runtimes", %{pod_id: pod_id, jido: jido} do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    assert {:ok, _report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("nested", %{
                   module: ReviewPod,
                   manager: @nested_pod_manager,
                   kind: :pod,
                   activation: :eager
                 })
               ]
             )

    assert {:ok, nested_pid} = Pod.lookup_node(pod_pid, "nested")
    assert {:ok, nested_planner_pid} = Pod.lookup_node(nested_pid, :planner)

    assert {:ok, report} = Pod.mutate(pod_pid, [Mutation.remove_node("nested")])
    assert report.status == :completed

    eventually(fn -> not Process.alive?(nested_pid) end)
    eventually(fn -> not Process.alive?(nested_planner_pid) end)
  end

  test "failed runtime materialization keeps the persisted topology and returns a failed report",
       %{
         pod_id: pod_id,
         jido: jido
       } do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)

    assert {:error, report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("bad_nested", %{
                   module: AlternateReviewPod,
                   manager: @nested_pod_manager,
                   kind: :pod,
                   activation: :eager
                 })
               ]
             )

    assert report.status == :failed
    assert Map.has_key?(report.failures, "bad_nested")
    assert {:ok, topology} = Pod.fetch_topology(pod_pid)
    assert Map.has_key?(topology.nodes, "bad_nested")
    assert {:error, _reason} = Pod.lookup_node(pod_pid, "bad_nested")

    assert {:ok, follow_up_report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("reviewer", %{
                   agent: PodWorker,
                   manager: @reviewer_manager,
                   activation: :lazy
                 })
               ]
             )

    assert follow_up_report.status == :completed
    assert "reviewer" in follow_up_report.added
  end

  test "rejects a second mutation while one is already in flight", %{pod_id: pod_id, jido: jido} do
    {:ok, pod_pid} = AgentServer.start_link(agent: EmptyMutablePod, id: pod_id, jido: jido)
    :persistent_term.put({SlowMountPlugin, :notify_pid}, self())

    task =
      Task.async(fn ->
        Pod.mutate(
          pod_pid,
          [
            Mutation.add_node("slow_worker", %{
              agent: SlowBootWorker,
              manager: @slow_manager,
              activation: :eager
            })
          ]
        )
      end)

    assert_receive :slow_mount_started, 5_000

    assert {:error, :mutation_in_progress} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("reviewer", %{
                   agent: PodWorker,
                   manager: @reviewer_manager,
                   activation: :lazy
                 })
               ]
             )

    assert {:ok, _report} = Task.await(task, 10_000)

    assert {:ok, %{status: :completed}} =
             AgentServer.await_completion(
               pod_pid,
               timeout: 5_000,
               status_path: [:__pod__, :mutation, :status],
               result_path: [:__pod__, :mutation, :report],
               error_path: [:__pod__, :mutation, :error]
             )

    assert {:ok, follow_up_report} =
             Pod.mutate(
               pod_pid,
               [
                 Mutation.add_node("reviewer", %{
                   agent: PodWorker,
                   manager: @reviewer_manager,
                   activation: :lazy
                 })
               ]
             )

    assert follow_up_report.status == :completed
    assert "reviewer" in follow_up_report.added
  end

  test "in-turn mutation_effects uses the same mutation completion path", %{
    pod_id: pod_id,
    jido: jido
  } do
    {:ok, pod_pid} = AgentServer.start_link(agent: SelfMutatingPod, id: pod_id, jido: jido)

    assert {:ok, _agent} =
             AgentServer.call(pod_pid, Signal.new!("expand", %{}, source: "/test"))

    assert {:ok, %{status: :completed, result: report}} =
             AgentServer.await_completion(
               pod_pid,
               timeout: 5_000,
               status_path: [:__pod__, :mutation, :status],
               result_path: [:__pod__, :mutation, :report],
               error_path: [:__pod__, :mutation, :error]
             )

    assert report.status == :completed
    assert report.added == ["planner"]
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, "planner")
    assert Process.alive?(planner_pid)
  end
end
