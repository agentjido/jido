defmodule JidoTest.Persistence.ETSTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence.ETS

  defp unique_table(name) do
    :"test_persistence_#{name}_#{System.unique_integer([:positive])}"
  end

  test "conditional writes require the exact bytes or an absent key" do
    opts = [table: unique_table(:cas)]
    assert {:error, :conflict} = ETS.compare_and_swap("key", <<0>>, <<1>>, opts)
    assert :ok = ETS.compare_and_swap("key", :not_found, <<0, 255>>, opts)
    assert {:error, :conflict} = ETS.compare_and_swap("key", :not_found, <<1>>, opts)
    assert {:error, :conflict} = ETS.compare_and_swap("key", <<0>>, <<1>>, opts)
    assert {:ok, <<0, 255>>} = ETS.get("key", opts)
    assert :ok = ETS.compare_and_swap("key", <<0, 255>>, <<1>>, opts)
    assert {:ok, <<1>>} = ETS.get("key", opts)
    assert :ok = ETS.delete("key", opts)
    assert {:error, :conflict} = ETS.compare_and_swap("key", <<1>>, <<2>>, opts)
  end

  test "one concurrent writer wins for each expected value" do
    opts = [table: unique_table(:cas)]

    for {expected, round} <- [{:not_found, 1}, {<<0, 255>>, 2}] do
      if round == 2, do: assert(:ok = ETS.put("key", expected, opts))

      results =
        1..8
        |> Task.async_stream(
          fn n ->
            value = <<round, n>>
            {ETS.compare_and_swap("key", expected, value, opts), value}
          end,
          max_concurrency: 8,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 7
      assert {:ok, ^winner} = ETS.get("key", opts)
    end
  end

  test "gets, replaces, and deletes binary values" do
    opts = [table: unique_table(:lifecycle)]

    assert {:error, :not_found} = ETS.get("key", opts)
    assert :ok = ETS.put("key", <<1>>, opts)
    assert {:ok, <<1>>} = ETS.get("key", opts)
    assert :ok = ETS.put("key", <<2>>, opts)
    assert {:ok, <<2>>} = ETS.get("key", opts)
    assert :ok = ETS.delete("key", opts)
    assert {:error, :not_found} = ETS.get("key", opts)
    assert :ok = ETS.delete("key", opts)
  end

  test "isolates persistence tables" do
    opts_a = [table: unique_table(:a)]
    opts_b = [table: unique_table(:b)]

    assert :ok = ETS.put("key", "a", opts_a)
    assert :ok = ETS.put("key", "b", opts_b)
    assert {:ok, "a"} = ETS.get("key", opts_a)
    assert {:ok, "b"} = ETS.get("key", opts_b)
  end

  test "an on-demand table transfers to the Jido supervisor" do
    opts = [table: unique_table(:on_demand)]
    table = :"#{Keyword.fetch!(opts, :table)}_records"
    supervisor = Process.whereis(Jido.Supervisor)

    caller = spawn(fn -> :ok = ETS.put("key", "value", opts) end)

    monitor = Process.monitor(caller)
    assert_receive {:DOWN, ^monitor, :process, ^caller, _reason}
    assert :ets.info(table, :owner) == supervisor
    assert {:ok, "value"} = ETS.get("key", opts)
  end
end
