defmodule Jido.Examples.Durable.VMRecovery.DetsStore do
  @moduledoc "A single BEAM owns this small, synced DETS byte adapter."
  use GenServer
  @behaviour Jido.Persistence.Store

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :table))

  @impl Jido.Persistence.Store
  def validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) -> {:error, "options must be a keyword list"}
      Keyword.keys(opts) != [:server] -> {:error, "requires one unique :server option"}
      not is_atom(Keyword.fetch!(opts, :server)) -> {:error, ":server must be an atom"}
      true -> :ok
    end
  end

  @impl Jido.Persistence.Store
  def get(key, opts), do: GenServer.call(Keyword.fetch!(opts, :server), {:get, key})

  @impl Jido.Persistence.Store
  def compare_and_swap(key, expected, value, opts),
    do: GenServer.call(Keyword.fetch!(opts, :server), {:compare_and_swap, key, expected, value})

  @impl Jido.Persistence.Store
  def delete(key, opts),
    do: GenServer.call(Keyword.fetch!(opts, :server), {:delete, key})

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)
    table = Keyword.fetch!(opts, :table)
    path = opts |> Keyword.fetch!(:path) |> String.to_charlist()

    case :dets.open_file(table, file: path, type: :set) do
      {:ok, ^table} -> {:ok, table}
      error -> {:stop, error}
    end
  end

  @impl GenServer
  def handle_call({:get, key}, _, table), do: {:reply, read(table, key), table}

  def handle_call({:compare_and_swap, key, expected, value}, _, table) do
    result =
      case read(table, key) do
        {:error, :not_found} when expected == :not_found -> write(table, key, value)
        {:ok, ^expected} -> write(table, key, value)
        {:ok, _} -> {:error, :conflict}
        {:error, :not_found} -> {:error, :conflict}
        error -> error
      end

    {:reply, result, table}
  end

  def handle_call({:delete, key}, _, table) do
    result = with :ok <- :dets.delete(table, key), do: :dets.sync(table)
    {:reply, result, table}
  end

  defp read(table, key) do
    case :dets.lookup(table, key) do
      [{^key, bytes}] when is_binary(bytes) -> {:ok, bytes}
      [] -> {:error, :not_found}
      _ -> {:error, :invalid_value}
    end
  end

  defp write(table, key, value) do
    with :ok <- :dets.insert(table, {key, value}), do: :dets.sync(table)
  end

  @impl GenServer
  def terminate(_, table), do: :dets.close(table)
end
