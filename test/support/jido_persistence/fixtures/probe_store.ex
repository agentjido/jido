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
  def validate_options(opts) do
    allowed = [:store, :fault_revision, :write_result]

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [] and
         Keyword.keys(opts) == Enum.uniq(Keyword.keys(opts)) and is_pid(opts[:store]),
       do: :ok,
       else: {:error, :invalid_probe_store_options}
  end

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
    fault_revision = Keyword.get(opts, :fault_revision, 1)
    record_revision = record_revision(value)

    Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn records ->
      if Map.get(records, key, :not_found) == expected do
        result =
          case if(record_revision == fault_revision,
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

  defp record_revision(value) do
    case Jido.Persistence.Codec.Term.decode(value, []) do
      {:ok, %{rev: revision}} when is_integer(revision) -> revision
      _other -> nil
    end
  end

  @impl true
  def delete(key, opts),
    do: Elixir.Agent.update(Keyword.fetch!(opts, :store), &Map.delete(&1, key))

  @doc "Changes one stored record to test validation at the load boundary."
  def rewrite_record({__MODULE__, opts}, id, update) do
    key = Jido.Persistence.agent_key(Jido.Agent.Address.new!(namespace: "persistence-probe", id: id))

    with {:ok, bytes} <- get(key, opts),
         {:ok, record} <- Jido.Persistence.Codec.Term.decode(bytes, []),
         {:ok, updated} <- Jido.Persistence.Codec.Term.encode(update.(record)) do
      put(key, updated, opts)
    end
  end
end
