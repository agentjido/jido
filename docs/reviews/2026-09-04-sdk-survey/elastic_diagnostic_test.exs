Code.require_file("test/integration/elastic_group/example_test.exs")

defmodule JidoTest.Integration.ElasticGroupTest do
  use JidoTest.Case, async: false

  @moduletag :integration

  alias Jido.Actor.Server
  alias Jido.Signal.Bus
  alias JidoTest.Integration.ElasticGroup.{ControllerActor, Signals}

  test "an elastic group scales, reclaims failed work, drains, and returns to its minimum", %{
    jido: jido
  } do
    bus = start_supervised!({Bus, name: :elastic_group_bus})
    group_id = unique_id("elastic-group")
    {:ok, controller} = Jido.start_actor(jido, ControllerActor, id: group_id)

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

    eventually(fn -> actor_child_count(controller) == 4 end, timeout: 2_000)

    initial_children = actor_children(controller)
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

    eventually(fn -> actor_child_count(controller) == 12 end, timeout: 3_000)
    eventually(fn -> map_size(Server.actor(controller).state.in_flight) == 10 end, timeout: 2_000)

    original = actor_children(controller)["worker-1"]
    original_ref = Process.monitor(original.pid)
    Process.exit(original.pid, :kill)
    assert_receive {:DOWN, ^original_ref, :process, _pid, :killed}, 2_000

    restarted =
      eventually(
        fn ->
          case actor_children(controller)["worker-1"] do
            %{pid: pid} = child when pid != original.pid -> child
            _child -> nil
          end
        end,
        timeout: 3_000
      )

    eventually(fn -> Server.actor(controller).state.member_starts[restarted.id] == 2 end,
      timeout: 2_000
    )

    try do
      eventually(
        fn ->
          state = Server.actor(controller).state
          map_size(state.results) == 13 and state.queue == [] and state.in_flight == %{}
        end,
        timeout: 5_000
      )
    rescue
      error ->
        IO.inspect(
          %{
            controller: Server.actor(controller).state,
            children:
              Map.new(actor_children(controller), fn {tag, child} ->
                {tag, Server.actor(child.pid).state}
              end)
          },
          label: "Elastic failure state",
          limit: :infinity
        )

        reraise error, __STACKTRACE__
    end

    assert Enum.any?(Server.actor(controller).state.exits, fn exit ->
             exit.member_id == restarted.id
           end)

    assert map_size(Server.actor(environment).state.results) == 13

    task_one = Server.actor(environment).state.results["elastic-task-1"]

    duplicate =
      Signals.environment_apply(
        group_id,
        Server.actor(controller).state.generation,
        task_one.worker_id,
        "elastic-task-1",
        task_one.result
      )

    assert {:ok, [_recorded]} = Bus.publish(bus, [duplicate])
    eventually(fn -> Server.actor(environment).state.duplicates == 1 end)
    assert map_size(Server.actor(controller).state.results) == 13

    monitor_state = Server.actor(monitor).state
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
        state = Server.actor(controller).state
        actor_child_count(controller) == 4 and state.draining_workers == []
      end,
      timeout: 3_000
    )

    assert Process.alive?(environment)
    assert Process.alive?(monitor)
    assert actor_children(controller).environment.pid == environment
    assert actor_children(controller).monitor.pid == monitor

    for index <- 3..10 do
      assert Jido.whereis_actor(jido, "#{group_id}/worker-#{index}") == nil
    end

    final_tasks = [
      %{id: "elastic-task-14", value: 14, delay_ms: 20},
      %{id: "elastic-task-15", value: 15, delay_ms: 20}
    ]

    assert {:ok, minimum_work} =
             Server.call(controller, signal("elastic.tasks.enqueue", %{tasks: final_tasks}))

    assert length(minimum_work.state.desired_workers) == 2

    eventually(fn -> map_size(Server.actor(controller).state.results) == 15 end,
      timeout: 3_000
    )

    all_child_pids = Server.children(controller) |> Map.values() |> Enum.map(& &1.pid)
    child_refs = Enum.map(all_child_pids, &{&1, Process.monitor(&1)})

    assert :ok = Jido.stop_actor(jido, controller)

    Enum.each(child_refs, fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
    end)

    eventually(fn -> Jido.actor_count(jido) == 0 end)
  end

  defp actor_child_count(controller), do: map_size(actor_children(controller))

  defp actor_children(controller) do
    controller
    |> Server.children()
    |> Map.filter(fn {_tag, child} -> child.kind == :actor end)
  end

  defp contains_pid?(value) when is_pid(value), do: true

  defp contains_pid?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, item} -> contains_pid?(item) end)

  defp contains_pid?(value) when is_list(value), do: Enum.any?(value, &contains_pid?/1)
  defp contains_pid?(_value), do: false
end
