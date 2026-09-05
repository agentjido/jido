defmodule Jido.Examples.PersistenceProbeStore do
  @moduledoc """
  In-memory byte adapter for the three persistence boundary examples.

  The caller owns the Elixir.Agent process. Conditional writes are atomic within that
  process. `write_result: :indeterminate` stores the value, then reports an
  unknown outcome. This is a controlled fault fixture, not durable storage.
  """
  use Elixir.Agent
  @behaviour Jido.Persistence.Adapter

  def start_link(_opts), do: Elixir.Agent.start_link(fn -> %{} end)

  @impl true
  def get(key, opts) do
    Elixir.Agent.get(Keyword.fetch!(opts, :store), fn records ->
      case Map.fetch(records, key) do
        {:ok, value} -> {:ok, value}
        :error -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def put(key, value, opts),
    do: Elixir.Agent.update(Keyword.fetch!(opts, :store), &Map.put(&1, key, value))

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn records ->
      if Map.get(records, key, :not_found) == expected do
        result =
          case Keyword.get(opts, :write_result, :ok) do
            :ok -> :ok
            :indeterminate -> {:error, :indeterminate}
          end

        {result, Map.put(records, key, value)}
      else
        {{:error, :conflict}, records}
      end
    end)
  end

  @impl true
  def delete(key, opts),
    do: Elixir.Agent.update(Keyword.fetch!(opts, :store), &Map.delete(&1, key))

  @doc "Changes a stored record to exercise validation at the load boundary."
  def rewrite_record({__MODULE__, opts}, module, id, update) do
    key = Jido.Persistence.agent_key(nil, module, id)

    with {:ok, bytes} <- get(key, opts) do
      record = :erlang.binary_to_term(bytes, [:safe])
      put(key, :erlang.term_to_binary(update.(record)), opts)
    end
  end
end
