defmodule Jido.Test.Persistence.ProbeStore do
  @moduledoc """
  In-memory byte adapter for persistence boundary tests and examples.

  The caller owns the Elixir.Agent process. Conditional writes are atomic in
  that process. `write_result: :indeterminate` stores the selected Agent
  revision and then reports an unknown outcome. `fault_revision:` defaults to
  one. Other values and execution checkpoint records stay confirmed.
  """
  use Elixir.Agent
  @behaviour Jido.Persistence.Store

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
    record = :erlang.binary_to_term(value, [:safe])
    fault_revision = Keyword.get(opts, :fault_revision, 1)

    Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn records ->
      if Map.get(records, key, :not_found) == expected do
        result =
          case if(match?(%{rev: ^fault_revision}, record),
                 do: Keyword.get(opts, :write_result, :ok),
                 else: :ok
               ) do
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

  @doc "Changes one stored record to test validation at the load boundary."
  def rewrite_record({__MODULE__, opts}, id, update) do
    key = Jido.Persistence.agent_key(Jido.Agent.Ref.new!(namespace: "persistence-probe", id: id))

    with {:ok, bytes} <- get(key, opts) do
      record = :erlang.binary_to_term(bytes, [:safe])
      put(key, :erlang.term_to_binary(update.(record)), opts)
    end
  end
end
