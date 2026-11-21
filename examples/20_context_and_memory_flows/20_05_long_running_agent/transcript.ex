defmodule Jido.Examples.ContextMemory.LongRunning.Transcript do
  @moduledoc "A local, single-writer DETS archive for one conversation."

  def open(name, path) do
    :dets.open_file(name, file: String.to_charlist(path), repair: true)
  end

  def close(table), do: :dets.close(table)

  def count(table) do
    metadata = Enum.count([:pending, :summary], &:dets.member(table, &1))
    :dets.info(table, :size) - metadata
  end

  def read(table, number) when is_integer(number) and number > 0, do: lookup(table, number)
  def pending(table), do: lookup(table, :pending)

  def summary(table) do
    case lookup(table, :summary) do
      {:ok, summary} -> summary
      {:error, :not_found} -> %{through: 0, text: nil}
    end
  end

  def reserve(table, request) do
    with {:ok, true} <- insert_new(table, :pending, request), do: :ok
  end

  def append(table, %{number: number} = turn) do
    case insert_new(table, number, turn) do
      {:ok, true} -> :ok
      {:error, :already_exists} -> check_record(table, number, turn)
      {:error, _reason} = error -> error
    end
  end

  def save_summary(table, summary) do
    with :ok <- :dets.insert(table, {:summary, summary}), do: :dets.sync(table)
  end

  def clear_pending(table) do
    with :ok <- :dets.delete(table, :pending), do: :dets.sync(table)
  end

  defp insert_new(table, key, value) do
    case :dets.insert_new(table, {key, value}) do
      true ->
        with :ok <- :dets.sync(table), do: {:ok, true}

      false ->
        {:error, :already_exists}

      {:error, _reason} = error ->
        error
    end
  end

  defp check_record(table, number, turn) do
    case read(table, number) do
      {:ok, ^turn} -> :dets.sync(table)
      {:ok, _other} -> {:error, :conflicting_turn}
      {:error, _reason} = error -> error
    end
  end

  defp lookup(table, key) do
    case :dets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end
end
