defmodule Jido.Examples.Persistence.IndeterminateStore do
  @moduledoc """
  A deterministic local store that can lose one write acknowledgement.

  The adapter saves the selected Agent revision, then returns
  `{:error, :indeterminate}`. This preserves the real persistence boundary:
  the caller cannot know from the reply whether the write took effect.

  This fault fixture is coupled to the public Term codec only to select the
  revision where it loses the acknowledgement. A normal byte Store does not
  inspect values.
  """

  use Elixir.Agent

  @behaviour Jido.Persistence.Store

  @option_keys [:store, :fault_revision]

  def start_link(_opts), do: Elixir.Agent.start_link(fn -> %{} end)

  @impl true
  def validate_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts),
      do: validate_keyword_options(opts),
      else: {:error, :options_must_be_a_keyword_list}
  end

  def validate_options(_opts), do: {:error, :options_must_be_a_keyword_list}

  defp validate_keyword_options(opts) do
    keys = Keyword.keys(opts)
    unknown = keys -- @option_keys
    duplicates = keys -- Enum.uniq(keys)

    cond do
      unknown != [] ->
        {:error, {:unknown_options, Enum.uniq(unknown)}}

      duplicates != [] ->
        {:error, {:duplicate_options, Enum.uniq(duplicates)}}

      not is_pid(Keyword.get(opts, :store)) ->
        {:error, {:invalid_option, :store}}

      not is_integer(Keyword.get(opts, :fault_revision)) ->
        {:error, {:invalid_option, :fault_revision}}

      Keyword.fetch!(opts, :fault_revision) < 1 ->
        {:error, {:invalid_option, :fault_revision}}

      true ->
        :ok
    end
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
    fault_revision = Keyword.fetch!(opts, :fault_revision)
    record_revision = record_revision(value)

    Elixir.Agent.get_and_update(Keyword.fetch!(opts, :store), fn records ->
      if Map.get(records, key, :not_found) == expected do
        result = if record_revision == fault_revision, do: {:error, :indeterminate}, else: :ok
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
end
