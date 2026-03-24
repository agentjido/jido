defmodule JidoTest.Pod.TelemetryTest do
  use JidoTest.Case, async: false

  alias Jido.Agent.InstanceManager
  alias Jido.Pod
  alias Jido.Storage.ETS

  @planner_manager :pod_telemetry_planner_members
  @reviewer_manager :pod_telemetry_reviewer_members
  @pod_manager :pod_telemetry_review_pods

  defmodule PodWorker do
    @moduledoc false
    use Jido.Agent,
      name: "pod_telemetry_worker",
      schema: [
        role: [type: :string, default: "worker"]
      ]
  end

  defmodule ReviewPod do
    @moduledoc false
    use Jido.Pod,
      name: "telemetry_review_pod",
      topology: %{
        planner: %{
          agent: PodWorker,
          manager: :pod_telemetry_planner_members,
          activation: :eager,
          initial_state: %{role: "planner"}
        },
        reviewer: %{
          agent: PodWorker,
          manager: :pod_telemetry_reviewer_members,
          activation: :lazy,
          initial_state: %{role: "reviewer"}
        }
      }
  end

  setup %{jido: jido} do
    test_pid = self()
    handler_id = "pod-telemetry-handler-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :pod, :reconcile, :start],
        [:jido, :pod, :reconcile, :stop],
        [:jido, :pod, :reconcile, :exception],
        [:jido, :pod, :node, :ensure, :start],
        [:jido, :pod, :node, :ensure, :stop],
        [:jido, :pod, :node, :ensure, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    storage_table = :"pod_telemetry_storage_#{System.unique_integer([:positive])}"

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
      :telemetry.detach(handler_id)
      :persistent_term.erase({InstanceManager, @planner_manager})
      :persistent_term.erase({InstanceManager, @reviewer_manager})
      :persistent_term.erase({InstanceManager, @pod_manager})
    end)

    {:ok, pod_key: "order-telemetry-123"}
  end

  test "Pod.get emits reconcile and ensure telemetry for eager nodes", %{pod_key: pod_key} do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert is_pid(pod_pid)

    assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :start], %{system_time: _},
                    %{pod_id: ^pod_key, pod_module: ReviewPod, jido_instance: _}}

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                    %{
                      node_name: :planner,
                      node_kind: :agent,
                      node_manager: @planner_manager,
                      source: :started,
                      pod_id: ^pod_key
                    }}

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: duration},
                    %{node_name: :planner, source: :started, pod_module: ReviewPod}}

    assert duration >= 0

    assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :stop],
                    %{duration: duration, node_count: 1},
                    %{pod_id: ^pod_key, pod_module: ReviewPod}}

    assert duration >= 0

    assert {:ok, _reviewer_pid} = Pod.ensure_node(pod_pid, :reviewer)

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                    %{
                      node_name: :reviewer,
                      node_kind: :agent,
                      node_manager: @reviewer_manager,
                      source: :started
                    }}

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                    %{node_name: :reviewer, source: :started}}
  end

  test "thaw plus reconcile emits running-source telemetry for surviving eager nodes", %{
    pod_key: pod_key
  } do
    assert {:ok, pod_pid} = Pod.get(@pod_manager, pod_key)
    assert {:ok, planner_pid} = Pod.lookup_node(pod_pid, :planner)

    drain_telemetry_events()

    pod_ref = Process.monitor(pod_pid)
    assert :ok = InstanceManager.stop(@pod_manager, pod_key)
    assert_receive {:DOWN, ^pod_ref, :process, ^pod_pid, _reason}, 1_000
    assert Process.alive?(planner_pid)

    assert {:ok, restored_pid} = InstanceManager.get(@pod_manager, pod_key)
    assert {:ok, _started} = Pod.reconcile(restored_pid)

    assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :start], %{system_time: _},
                    %{pod_id: ^pod_key, pod_module: ReviewPod}}

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :start], %{system_time: _},
                    %{node_name: :planner, source: :running, node_manager: @planner_manager}}

    assert_receive {:telemetry_event, [:jido, :pod, :node, :ensure, :stop], %{duration: _},
                    %{node_name: :planner, source: :running}}

    assert_receive {:telemetry_event, [:jido, :pod, :reconcile, :stop],
                    %{duration: _, node_count: 1}, %{pod_id: ^pod_key, pod_module: ReviewPod}}
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
