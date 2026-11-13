defmodule Jido.Examples.Persistence.IndeterminateStore do
  @moduledoc """
  A deterministic local store that can lose one write acknowledgement.

  The adapter saves the selected Agent revision, then returns
  `{:error, :indeterminate}`. This preserves the real persistence boundary:
  the caller cannot know from the reply whether the write took effect.
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
    fault_revision = Keyword.fetch!(opts, :fault_revision)

    Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn records ->
      if Map.get(records, key, :not_found) == expected do
        result =
          if match?(%{rev: ^fault_revision}, record),
            do: {:error, :indeterminate},
            else: :ok

        {result, Map.put(records, key, value)}
      else
        {{:error, :conflict}, records}
      end
    end)
  end

  @impl true
  def delete(key, opts),
    do: Elixir.Agent.update(Keyword.fetch!(opts, :store), &Map.delete(&1, key))
end
