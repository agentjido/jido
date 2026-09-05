Code.require_file("example_test.exs", __DIR__)

defmodule JidoTest.Integration.ElasticGroupTest do
  use JidoTest.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Signal.Bus
  alias JidoTest.Integration.ElasticGroup.{ControllerAgent, Signals}

  test "an elastic group scales, reclaims failed work, drains, and returns to its minimum", %{
    jido: jido
  } do
    bus = start_supervised!({Bus, name: :elastic_group_bus, jido: jido})
    group_id = unique_id("elastic-group")
    {:ok, controller} = Jido.start_agent(jido, ControllerAgent, id: group_id)

    assert {:ok, started} =
             Server.call(
               controller,
               signal("elastic.group.start", %{
                 group_id: group_id,
                 min_workers: 2,
                 max_workers: 10
               })
             )

    assert length(started.state.desired_workers) == 2
    refute contains_pid?(started.state)

    eventually(fn -> agent_child_count(controller) == 4 end, timeout: 2_000)

    initial_children = agent_children(controller)
    environment = initial_children.environment.pid
    monitor = initial_children.monitor.pid

    tasks =
      Enum.map(1..13, fn index ->
        delay_ms = if index == 1, do: 5_000, else: 80

        %{
          id: "elastic-task-#{index}",
          value: index,
          delay_ms: delay_ms,
          retry_delay_ms: 20
        }
      end)

    assert {:ok, scaled} =
             Server.call(controller, signal("elastic.tasks.enqueue", %{tasks: tasks}))

    assert length(scaled.state.desired_workers) == 10

    eventually(fn -> agent_child_count(controller) == 12 end, timeout: 3_000)
    eventually(fn -> map_size(Server.agent(controller).state.in_flight) == 10 end, timeout: 2_000)

    original = agent_children(controller)["worker-1"]
    eventually(fn -> Server.agent(original.pid).state.current_task[:id] == "elastic-task-1" end)
    original_ref = Process.monitor(original.pid)
    Process.exit(original.pid, :kill)
    assert_receive {:DOWN, ^original_ref, :process, _pid, :killed}, 2_000

    restarted =
      eventually(
        fn ->
          case agent_children(controller)["worker-1"] do
            %{pid: pid} = child when pid != original.pid -> child
            _child -> nil
          end
        end,
        timeout: 3_000
      )

    eventually(fn -> Server.agent(controller).state.member_starts[restarted.id] == 2 end,
      timeout: 2_000
    )

    eventually(
      fn ->
        state = Server.agent(controller).state
        map_size(state.results) == 13 and state.queue == [] and state.in_flight == %{}
      end,
      timeout: 5_000
    )

    assert Enum.any?(Server.agent(controller).state.exits, fn exit ->
             exit.member_id == restarted.id
           end)

    assert map_size(Server.agent(environment).state.results) == 13

    task_one = Server.agent(environment).state.results["elastic-task-1"]

    assert task_one.attempt == 2

    duplicate =
      Signals.environment_apply(
        group_id,
        Server.agent(controller).state.generation,
        task_one.worker_id,
        "elastic-task-1",
        task_one.result,
        task_one.attempt
      )

    assert {:ok, [_recorded]} = Bus.publish(bus, [duplicate])
    eventually(fn -> Server.agent(environment).state.duplicates == 1 end)
    assert map_size(Server.agent(controller).state.results) == 13

    monitor_state = Server.agent(monitor).state
    assert Map.get(monitor_state.counts, "elastic.control.worker.failed", 0) >= 1
    assert Map.get(monitor_state.counts, "elastic.control.worker.busy", 0) >= 10

    assert {:ok, first_low} = Server.call(controller, signal("elastic.scale.observe"))
    assert first_low.state.low_observations == 1
    assert length(first_low.state.desired_workers) == 10
    assert first_low.state.draining_workers == []

    assert {:ok, scale_down} = Server.call(controller, signal("elastic.scale.observe"))
    assert length(scale_down.state.desired_workers) == 2
    assert length(scale_down.state.draining_workers) == 8

    eventually(
      fn ->
        state = Server.agent(controller).state
        agent_child_count(controller) == 4 and state.draining_workers == []
      end,
      timeout: 3_000
    )

    assert Process.alive?(environment)
    assert Process.alive?(monitor)
    assert agent_children(controller).environment.pid == environment
    assert agent_children(controller).monitor.pid == monitor

    for index <- 3..10 do
      assert Jido.whereis_agent(jido, "#{group_id}/worker-#{index}") == nil
    end

    final_tasks = [
      %{id: "elastic-task-14", value: 14, delay_ms: 20},
      %{id: "elastic-task-15", value: 15, delay_ms: 20}
    ]

    assert {:ok, minimum_work} =
             Server.call(controller, signal("elastic.tasks.enqueue", %{tasks: final_tasks}))

    assert length(minimum_work.state.desired_workers) == 2

    eventually(fn -> map_size(Server.agent(controller).state.results) == 15 end,
      timeout: 3_000
    )

    all_child_pids = Server.children(controller) |> Map.values() |> Enum.map(& &1.pid)
    child_refs = Enum.map(all_child_pids, &{&1, Process.monitor(&1)})

    assert :ok = Jido.stop_agent(jido, controller)

    Enum.each(child_refs, fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
    end)

    eventually(fn -> Jido.agent_count(jido) == 0 end)
  end

  test "restored work rejects old attempts and the controller accepts only its saved attempt" do
    alias JidoTest.Integration.ElasticGroup.WorkerAgent

    worker =
      WorkerAgent.new!(
        id: "worker",
        state: %{group_id: "group", member_id: "worker", generation: 1}
      )

    task = %{id: "task", value: 7, delay_ms: 5_000, attempt: 1}

    assert {:ok, busy, [_busy, _timer]} =
             WorkerAgent.cmd(worker, Signals.work_requested("group", 1, "worker", task))

    assert {:ok, checkpoint} = Jido.Agent.checkpoint(busy)
    assert {:ok, restored} = Jido.Agent.restore(WorkerAgent, checkpoint)
    retry = %{task | attempt: 2, delay_ms: 20}

    assert {:ok, retrying, [_busy, _timer]} =
             WorkerAgent.cmd(restored, Signals.work_requested("group", 1, "worker", retry))

    old = %{
      group_id: "group",
      generation: 1,
      worker_id: "worker",
      task_id: "task",
      value: 7,
      attempt: 1
    }

    assert {:ok, rejected, []} = WorkerAgent.cmd(retrying, Signals.worker_finish(old))
    assert rejected.state.current_task.attempt == 2
    assert rejected.state.handled == []

    assert {:ok, done, [_result, _ready]} =
             WorkerAgent.cmd(rejected, Signals.worker_finish(%{old | attempt: 2}))

    assert done.state.handled == ["task"]

    assert {:ok, duplicate, []} =
             WorkerAgent.cmd(done, Signals.work_requested("group", 1, "worker", task))

    assert duplicate.state.handled == ["task"]
    assert duplicate.state.current_task == %{}

    controller =
      ControllerAgent.new!(
        state: %{
          group_id: "group",
          generation: 1,
          in_flight: %{"task" => %{worker_id: "worker", task: retry}}
        }
      )

    result = %{
      group_id: "group",
      generation: 1,
      task_id: "task",
      worker_id: "worker",
      result: 21,
      attempt: 1
    }

    assert {:ok, unchanged, []} = ControllerAgent.cmd(controller, Signals.work_completed(result))
    assert unchanged.state == controller.state

    assert {:ok, complete, []} =
             ControllerAgent.cmd(controller, Signals.work_completed(%{result | attempt: 2}))

    assert complete.state.in_flight == %{}
    assert complete.state.results["task"].attempt == 2
  end

  defp agent_child_count(controller), do: map_size(agent_children(controller))

  defp agent_children(controller) do
    controller
    |> Server.children()
    |> Map.filter(fn {_tag, child} -> child.kind == :agent end)
  end

  defp contains_pid?(value) when is_pid(value), do: true

  defp contains_pid?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, item} -> contains_pid?(item) end)

  defp contains_pid?(value) when is_list(value), do: Enum.any?(value, &contains_pid?/1)
  defp contains_pid?(_value), do: false
end
