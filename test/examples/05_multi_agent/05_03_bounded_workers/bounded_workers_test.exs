defmodule JidoTest.Examples.MultiAgent.BoundedWorkersTest do
  use JidoTest.FeatureSDKCase
  @moduletag group: :multi_agent
  alias Jido.Examples.{BoundedWorkers, Worker}

  defp start_pool(jido) do
    parent = start_agent!(jido, BoundedWorkers, error_policy: :log_only)

    assert {:ok, _} =
             BoundedWorkers.process_values(parent, "batch", [2, 3, 4, 5], 2,
               context: %{worker: observed(Worker, :on_work)}
             )

    workers =
      for _ <- 1..2 do
        assert_receive {:feature_work, pid, input}, 1_000
        {input.job_id, {pid, input}}
      end

    eventually(fn -> Server.snapshot(parent).state_version == 3 end)
    {parent, Map.new(workers)}
  end

  test "two live workers overlap, reuse their slots, and preserve input result order", %{
    jido: jido
  } do
    {parent, workers} = start_pool(jido)
    assert map_size(Server.children(parent)) == 2
    assert length(state(parent).queue) == 2
    {first, _} = workers["0"]
    {second, _} = workers["1"]
    assert first != second
    send(second, :release)
    assert_receive {:feature_work, third, %{job_id: "2", tag: "slot-1"}}, 1_000
    assert state(parent).results == %{"1" => 6}
    assert map_size(Server.children(parent)) == 2
    send(third, :release)
    assert_receive {:feature_work, fourth, %{job_id: "3", tag: "slot-1"}}, 1_000
    send(fourth, :release)
    eventually(fn -> map_size(state(parent).results) == 3 end)
    assert state(parent).status == :running
    send(first, :release)
    eventually(fn -> state(parent).status == :completed end)
    assert BoundedWorkers.ordered_results(Server.agent(parent)) == [4, 6, 8, 10]
    eventually(fn -> Server.children(parent) == %{} end)
  end

  test "stale replies cannot consume a slot or advance the queue", %{jido: jido} do
    {parent, workers} = start_pool(jido)
    before = Server.snapshot(parent)
    {_pid, input} = workers["0"]

    for overrides <- [%{request_id: "old"}, %{tag: "unknown"}, %{job_id: "100"}] do
      assert {:error, _} =
               Server.call(parent, signal("examples.work.result", Map.merge(input, overrides)))

      assert Server.snapshot(parent) == before
    end

    assert {:ok, _} = BoundedWorkers.cancel(parent)
    eventually(fn -> Server.children(parent) == %{} end)
  end

  test "cancellation stops all child execution and discards queued work", %{jido: jido} do
    {parent, workers} = start_pool(jido)
    monitors = Enum.map(workers, fn {_, {pid, _}} -> {pid, Process.monitor(pid)} end)
    assert {:ok, _} = BoundedWorkers.cancel(parent)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    eventually(fn -> Server.children(parent) == %{} end)
    assert state(parent).status == :cancelled
    assert state(parent).queue == []
    refute_receive {:feature_work, _, _}, 20
  end

  test "one child crash fails the request and stops the sibling", %{jido: jido} do
    {parent, workers} = start_pool(jido)
    monitors = Enum.map(workers, fn {_, {pid, _}} -> {pid, Process.monitor(pid)} end)
    Process.exit(Server.children(parent)["slot-0"].pid, :kill)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    eventually(fn -> state(parent).status == :failed and Server.children(parent) == %{} end)
    assert state(parent).results == %{}
  end

  test "empty input starts no child and invalid limits make no commit", %{jido: jido} do
    parent = start_agent!(jido, BoundedWorkers, error_policy: :log_only)
    assert {:ok, empty} = BoundedWorkers.process_values(parent, "empty", [])
    assert empty.state.status == :completed
    assert Server.children(parent) == %{}
    before = Server.snapshot(parent)

    for limit <- [0, -1, 9] do
      assert {:error, _} = BoundedWorkers.process_values(parent, "invalid", [1], limit)
      assert Server.snapshot(parent) == before
    end
  end
end
