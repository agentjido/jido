Code.require_file("batch_processing.ex", __DIR__)

defmodule Jido.Examples.Patterns.BatchProcessingTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  test "keeps four Map items active and returns ordered output" do
    input = Enum.to_list(1..100)
    gate = make_ref()
    owner = self()

    task =
      Task.async(fn ->
        Jido.Exec.run(
          Jido.Examples.Patterns.BatchProcessing,
          %{items: input},
          %{gate: gate, observer: owner},
          max_concurrency: 4
        )
      end)

    first = receive_batch(4, [])
    assert Enum.sort(Enum.map(first, &elem(&1, 0))) == Enum.to_list(0..3)
    refute_receive {:batch_ready, _index, _pid}, 50
    Enum.each(first, fn {_index, pid} -> send(pid, {:release_batch, gate}) end)
    release_remaining(96, gate)

    assert {:ok, %{items: items, total: %{total: 10_100}}} = Task.await(task, 5_000)
    assert Enum.map(items, & &1.index) == Enum.to_list(0..99)
    assert Enum.map(items, & &1.value) == Enum.map(input, &(&1 * 2))
  end

  defp receive_batch(0, found), do: found

  defp receive_batch(remaining, found) do
    assert_receive {:batch_ready, index, pid}, 1_000
    receive_batch(remaining - 1, [{index, pid} | found])
  end

  defp release_remaining(0, _gate), do: :ok

  defp release_remaining(remaining, gate) do
    assert_receive {:batch_ready, _index, pid}, 1_000
    send(pid, {:release_batch, gate})
    release_remaining(remaining - 1, gate)
  end
end
