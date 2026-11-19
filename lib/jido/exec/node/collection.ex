defmodule Jido.Exec.Node.Collection do
  @moduledoc false

  alias Jido.Exec.Runtime

  @doc false
  @spec run(list(), :fail_fast | :collect_errors, (term() -> tuple())) :: [tuple()]
  def run(items, :collect_errors, work), do: Runtime.map_items(items, Runtime.max_concurrency(), work)

  def run(items, :fail_fast, work) do
    limit = Runtime.max_concurrency()

    items
    |> Stream.chunk_every(limit)
    |> Enum.reduce_while([], fn batch, preceding ->
      outcomes = run_batch(batch, limit, work)

      if Enum.all?(outcomes, &(elem(&1, 0) == :ok)) do
        {:cont, [outcomes | preceding]}
      else
        {:halt, [outcomes | preceding]}
      end
    end)
    |> Enum.reverse()
    |> Enum.concat()
  end

  defp run_batch(items, limit, work) when limit > 1, do: Runtime.map_items(items, limit, work)

  defp run_batch(items, _limit, work), do: Enum.map(items, work)
end
