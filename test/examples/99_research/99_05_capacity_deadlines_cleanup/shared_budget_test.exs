defmodule JidoTest.Examples.SharedBudgetTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.SharedBudget, as: Example

  setup %{jido: jido} do
    clock = start_supervised!({Elixir.Agent, fn -> 0 end})

    service =
      start_supervised!(
        {Example,
         jido: jido,
         observer: self(),
         limit: 2,
         queue_limit: 2,
         clock: fn -> Elixir.Agent.get(clock, & &1) end}
      )

    %{service: service, clock: clock}
  end

  test "concurrent teams share one active limit and one queue limit", c do
    results =
      1..5
      |> Task.async_stream(fn n ->
        Example.submit(c.service, "team-#{rem(n, 2)}", "job-#{n}", n, 100)
      end)
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 4
    assert Enum.count(results, &(&1 == {:error, :overloaded})) == 1
    assert_receive {:budget_work, first_id, first}, 1_000
    assert_receive {:budget_work, second_id, second}, 1_000
    status = Example.status(c.service)
    assert map_size(status.active) == 2
    assert length(status.queued) == 2
    assert status.peak == 2
    send(first, :finish)
    send(second, :finish)
    assert_receive {:budget_work, third_id, third}, 1_000
    assert_receive {:budget_work, fourth_id, fourth}, 1_000
    send(third, :finish)
    send(fourth, :finish)
    eventually(fn -> map_size(Example.status(c.service).results) == 4 end)
    status = Example.status(c.service)
    assert status.active == %{}
    assert status.queued == []
    assert status.peak == 2

    for id <- [first_id, second_id, third_id, fourth_id] do
      expected = id |> String.replace_prefix("job-", "") |> String.to_integer() |> Kernel.*(2)
      assert status.results[id] == {:ok, expected}
    end
  end

  test "expired queued jobs never start and worker loss releases capacity", c do
    assert :ok = Example.submit(c.service, "a", "first", 1, 100)
    assert :ok = Example.submit(c.service, "b", "second", 2, 100)
    assert_receive {:budget_work, "first", first}, 1_000
    assert_receive {:budget_work, "second", second}, 1_000
    assert :ok = Example.submit(c.service, "a", "expired", 3, 10)
    assert :ok = Example.submit(c.service, "b", "survivor", 4, 100)
    Elixir.Agent.update(c.clock, fn _ -> 20 end)
    assert :ok = Example.tick(c.service)
    assert Example.status(c.service).results["expired"] == {:error, :expired}
    server = Example.status(c.service).active["first"].server
    ref = Process.monitor(first)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^ref, :process, ^first, _}, 1_000
    assert_receive {:budget_work, "survivor", survivor}, 1_000
    send(second, :finish)
    send(survivor, :finish)
    eventually(fn -> map_size(Example.status(c.service).results) == 4 end)
    assert Example.status(c.service).results["first"] == {:error, :worker_lost}
    assert Example.status(c.service).results["survivor"] == {:ok, 8}
    refute_received {:budget_work, "expired", _}
  end

  test "service shutdown closes every active Agent, Action, and call Task", c do
    for n <- 1..2, do: assert(:ok == Example.submit(c.service, "team", "job-#{n}", n, 100))
    assert_receive {:budget_work, _, a}, 1_000
    assert_receive {:budget_work, _, b}, 1_000
    status = Example.status(c.service)

    pids =
      [a, b, status.task_supervisor] ++
        Enum.flat_map(status.active, fn {_, entry} -> [entry.server, entry.task] end)

    monitors = Enum.map(pids, &{&1, Process.monitor(&1)})
    assert :ok = stop_supervised(Example)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
  end
end
