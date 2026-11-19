defmodule Jido.Exec.Node.Collection do
  @moduledoc false

  alias Jido.Exec.Runtime

  @doc false
  @spec run(list(), :fail_fast | :collect_errors, (term() -> tuple())) :: [tuple()]
  def run([_, _ | _] = items, on_error, work),
    do: run(items, on_error, Runtime.max_concurrency(), work)

  def run(items, _on_error, work), do: Enum.map(items, work)

  defp run(items, :collect_errors, limit, work), do: run_batch(items, limit, work)

  defp run(items, :fail_fast, limit, work) do
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

  defp run_batch(items, limit, work) when limit > 1 do
    items
    |> Task.async_stream(work, max_concurrency: limit, timeout: :infinity, zip_input_on_exit: true)
    |> Enum.map(fn
      {:ok, outcome} -> outcome
      {:exit, {item, reason}} -> {:task_exit, item, reason}
    end)
  end

  defp run_batch(items, _limit, work), do: Enum.map(items, work)
end
