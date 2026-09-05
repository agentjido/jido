Code.require_file("test/integration/fixed_group/example_test.exs")

defmodule JidoTest.Integration.FixedGroupTest do
  use JidoTest.Case, async: false

  @moduletag :integration

  alias Jido.Actor.Server
  alias Jido.Signal.Bus
  alias JidoTest.Integration.FixedGroup.ControllerActor

  test "a fixed group owns stable children and coordinates work through the Bus", %{jido: jido} do
    bus = start_supervised!({Bus, name: :fixed_group_bus})
    group_id = unique_id("fixed-group")
    {:ok, controller} = Jido.start_actor(jido, ControllerActor, id: group_id)

    assert {:ok, started} =
             Server.call(
               controller,
               signal("fixed.group.start", %{group_id: group_id, worker_count: 3})
             )

    assert map_size(started.state.desired) == 4
    refute contains_pid?(started.state)

    eventually(fn -> length(Server.actor(controller).state.ready_members) == 4 end,
      timeout: 2_000
    )

    children = actor_children(controller)
    assert map_size(children) == 4
    assert children.environment.id == "#{group_id}/environment"

    for index <- 1..3 do
      assert children["worker-#{index}"].id == "#{group_id}/worker-#{index}"
    end

    try do
      eventually(
        fn ->
          {:ok, records} = Bus.replay(bus, "fixed.control.member.ready")
          length(records) == 4
        end,
        timeout: 2_000
      )
    rescue
      error ->
        IO.inspect(
          %{
            global_bus: Bus.whereis(:fixed_group_bus),
            scoped_bus: Bus.whereis(:fixed_group_bus, jido: jido),
            global_records: Bus.replay(bus, "fixed.control.member.ready"),
            controller: Server.actor(controller).state
          },
          label: "Fixed failure state",
          limit: :infinity
        )

        reraise error, __STACKTRACE__
    end

    tasks = Enum.map(1..6, &%{id: "task-#{&1}", value: &1})

    assert {:ok, submitted} =
             Server.call(controller, signal("fixed.work.submit", %{tasks: tasks}))

    assert map_size(submitted.state.submitted) == 6

    eventually(fn -> map_size(Server.actor(controller).state.results) == 6 end,
      timeout: 3_000
    )

    environment = children.environment.pid
    assert map_size(Server.actor(environment).state.results) == 6

    for index <- 1..3 do
      worker = children["worker-#{index}"].pid
      assert length(Server.actor(worker).state.handled) == 2
      assert Server.actor(worker).state.ignored == 4
    end

    original = children["worker-2"]
    original_ref = Process.monitor(original.pid)
    Process.exit(original.pid, :kill)
    assert_receive {:DOWN, ^original_ref, :process, _pid, :killed}, 2_000

    restarted =
      eventually(
        fn ->
          case Server.children(controller)["worker-2"] do
            %{pid: pid} = child when pid != original.pid -> child
            _child -> nil
          end
        end,
        timeout: 3_000
      )

    assert restarted.id == original.id

    eventually(fn -> Server.actor(controller).state.member_starts[restarted.id] == 2 end)

    more_tasks = Enum.map(7..9, &%{id: "task-#{&1}", value: &1})

    assert {:ok, _submitted} =
             Server.call(controller, signal("fixed.work.submit", %{tasks: more_tasks}))

    eventually(fn -> map_size(Server.actor(controller).state.results) == 9 end,
      timeout: 3_000
    )

    assert Server.actor(restarted.pid).state.handled == ["task-8"]

    child_pids = Server.children(controller) |> Map.values() |> Enum.map(& &1.pid)
    child_refs = Enum.map(child_pids, &{&1, Process.monitor(&1)})

    assert :ok = Jido.stop_actor(jido, controller)

    Enum.each(child_refs, fn {pid, ref} ->
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 2_000
    end)

    eventually(fn -> Jido.actor_count(jido) == 0 end)
  end

  defp contains_pid?(value) when is_pid(value), do: true

  defp contains_pid?(value) when is_map(value),
    do: Enum.any?(value, fn {_key, item} -> contains_pid?(item) end)

  defp contains_pid?(value) when is_list(value), do: Enum.any?(value, &contains_pid?/1)
  defp contains_pid?(_value), do: false

  defp actor_children(controller) do
    controller
    |> Server.children()
    |> Map.filter(fn {_tag, child} -> child.kind == :actor end)
  end
end
