Code.require_file("example.ex", __DIR__)
Code.require_file("job_board.ex", __DIR__)
Code.require_file("support/store_fixture.exs", __DIR__)

defmodule Jido.Examples.SharedBlackboardSwarmTest do
  use Jido.Test.Case, async: false

  alias Jido.{AgentServer, Blackboard, Statechart}
  alias Jido.Examples.SharedBlackboard.{Counter, JobBoard, StoreFixture}
  alias Jido.Plugin.Blackboard.Client

  @moduletag :integration
  @timeout 15_000

  for counter_count <- [20, 100] do
    test "#{counter_count} counters can share one durable board or use a board for each job" do
      instance = __MODULE__.Inventory
      count = unquote(counter_count)
      adapter = sample_adapter()
      profile = StoreFixture.profile(adapter)

      start_supervised!({Jido, name: instance, namespace: unique_id("inventory-swarm"), persistence: profile})

      exercise(instance, adapter, "shared", count, 1)
      exercise(instance, adapter, "by-job", count, div(count, 5))
    end
  end

  defp exercise(instance, adapter, label, count, board_count) do
    boards =
      for index <- 1..board_count do
        name = "#{label}-#{index}"
        assert {:ok, address} = JobBoard.create(instance, name)
        assert {:ok, owner} = Jido.activate_agent(instance, address)
        {name, owner}
      end

    counters =
      for index <- 1..count do
        {board, _owner} = Enum.at(boards, rem(index - 1, board_count))
        id = "#{label}/counter/#{index}"

        assert {:ok, pid} =
                 Jido.start_agent(instance, Counter,
                   id: id,
                   plugin_runtime_options: [{Client, [name: board, timeout: 2_500]}]
                 )

        assert :ok = AgentServer.await_ready(pid, @timeout)
        {board, pid, id, index}
      end

    read_times =
      parallel(counters, fn {_board, pid, id, _count} ->
        assert {:ok, %{status: :committed}} = Statechart.initialize(pid, %{"request_id" => id})

        {elapsed, result} =
          :timer.tc(fn -> AgentServer.call(pid, Counter.read_signal!(%{}), @timeout) end)

        assert {:ok, %{status: :committed}} = result
        elapsed
      end)

    {write_time, results} =
      :timer.tc(fn ->
        parallel(counters, fn {board, pid, id, index} ->
          signal = Counter.count_signal!(%{count: index, request_id: id})
          assert {:ok, %{status: :committed}} = AgentServer.call(pid, signal, @timeout)

          outcome =
            eventually(
              fn ->
                case Statechart.session(pid) do
                  %{state: "recorded"} -> "ok"
                  %{state: "read_again", data: %{"outcome" => status}} -> status
                  _waiting -> nil
                end
              end,
              timeout: @timeout
            )

          {board, outcome, index}
        end)
      end)

    grouped = Enum.group_by(results, &elem(&1, 0))

    for {board, owner} <- boards do
      assert [{^board, "ok", winner}] = Enum.filter(Map.fetch!(grouped, board), &match?({_, "ok", _}, &1))

      assert {:ok, %{values: %{"bin-a" => ^winner}}} = Blackboard.read(instance, board)
      assert :ok = Jido.stop_agent(instance, owner)
      assert {:error, :unavailable} = Blackboard.read(instance, board)
    end

    assert Enum.count(results, &match?({_, "conflict", _}, &1)) == count - board_count
    report_sample(adapter, label, count, board_count, read_times, write_time)
    Enum.each(counters, fn {_board, pid, _id, _count} -> assert :ok = Jido.stop_agent(instance, pid) end)
  end

  defp parallel(counters, fun) do
    counters
    |> Task.async_stream(fun, max_concurrency: length(counters), ordered: false, timeout: @timeout * 3)
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp sample_adapter do
    case System.get_env("JIDO_BLACKBOARD_STORE", "ets") do
      "ets" -> :ets
      "mnesia" -> :mnesia
      "ecto" -> :ecto
      _other -> flunk("Set JIDO_BLACKBOARD_STORE to ets, mnesia, or ecto")
    end
  end

  defp report_sample(adapter, label, count, board_count, reads, writes) do
    if System.get_env("JIDO_BLACKBOARD_SAMPLE") == "1" do
      p95 = reads |> Enum.sort() |> Enum.at(ceil(count * 0.95) - 1)

      IO.puts(
        "#{adapter} #{label}, counters #{count}, boards #{board_count}, conflicts #{count - board_count}, " <>
          "read Turn p95 #{p95} us, write burst with results #{writes} us"
      )
    end
  end
end
