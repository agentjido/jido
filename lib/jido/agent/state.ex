defmodule Jido.Agent.State do
  @moduledoc """
  Internal helper module for agent state management.

  > #### Internal Module {: .warning}
  > This module is internal to the Agent implementation. Its API may
  > change without notice.

  Handles deep merging and validation of agent state.
  """

  alias Jido.Action.Schema

  @doc """
  Merges new attributes into existing state using deep merge semantics.
  """
  @spec merge(map(), map() | keyword()) :: map()
  def merge(current_state, attrs) when is_list(attrs) do
    merge(current_state, Map.new(attrs))
  end

  def merge(current_state, attrs) when is_map(attrs) do
    DeepMerge.deep_merge(current_state, attrs)
  end

  @doc """
  Validates state against a schema (NimbleOptions or Zoi).
  Returns validated state as a map.

  By default (non-strict mode), extra fields not in the schema are preserved.
  In strict mode, only schema-defined fields are kept.
  """
  @spec validate(map(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(state, schema, opts \\ [])

  def validate(state, [], _opts), do: {:ok, state}

  def validate(state, schema, opts) when is_list(schema) do
    strict? = Keyword.get(opts, :strict, false)
    known_keys = Keyword.keys(schema)

    state_to_validate = Map.take(state, known_keys)
    extra_fields = Map.drop(state, known_keys)

    case Schema.validate(schema, state_to_validate) do
      {:ok, validated} ->
        if strict? do
          {:ok, validated}
        else
          {:ok, Map.merge(validated, extra_fields)}
        end

      {:error, _} = error ->
        error
    end
  end

  def validate(state, schema, opts) do
    strict? = Keyword.get(opts, :strict, false)

    case Schema.validate(schema, state) do
      {:ok, validated} ->
        if strict? do
          {:ok, validated}
        else
          known_keys = Schema.known_keys(schema)
          extra_fields = Map.drop(state, known_keys)
          {:ok, Map.merge(validated, extra_fields)}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Builds initial state from schema defaults.
  """
  @spec defaults_from_schema(term()) :: map()
  def defaults_from_schema([]), do: %{}

  def defaults_from_schema(schema) when is_list(schema) do
    Enum.reduce(schema, %{}, fn {key, opts}, acc ->
      case Keyword.fetch(opts, :default) do
        {:ok, default} -> Map.put(acc, key, default)
        :error -> acc
      end
    end)
  end

  def defaults_from_schema(zoi_schema) do
    Jido.Agent.Schema.defaults_from_zoi_schema(zoi_schema)
  end
end
