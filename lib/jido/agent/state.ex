defmodule Jido.Agent.State do
  @moduledoc """
  Internal helper module for agent state management.

  > #### Internal Module {: .warning}
  > This module is internal to the Agent implementation. Its API may
  > change without notice.

  Handles deep merging and validation of agent state.
  """

  alias Jido.Util.DeepMerge

  @doc false
  @spec validate_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_schema(value, opts \\ [])

  def validate_schema([], _opts), do: :ok

  def validate_schema(%Zoi.Types.Map{fields: fields}, _opts) when is_list(fields), do: :ok

  def validate_schema(_value, _opts),
    do: {:error, "must be a field-based Zoi map schema"}

  @doc """
  Merges new attributes into existing state using recursive map and keyword-list semantics.
  """
  @spec merge(map(), map() | keyword()) :: map()
  def merge(current_state, attrs) when is_list(attrs) do
    merge(current_state, Map.new(attrs))
  end

  def merge(current_state, attrs) when is_map(attrs) do
    DeepMerge.merge(current_state, attrs)
  end

  @doc """
  Validates state against a Zoi schema.
  Returns validated state as a map.

  By default (non-strict mode), extra fields not in the schema are preserved.
  In strict mode, only schema-defined fields are kept.
  """
  @spec validate(map(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(state, schema, opts \\ [])

  def validate(state, [], _opts), do: {:ok, state}

  def validate(state, %Zoi.Types.Map{} = schema, opts) do
    unrecognized_keys = if Keyword.get(opts, :strict, false), do: :strip, else: :preserve
    Zoi.parse(%{schema | unrecognized_keys: unrecognized_keys}, state)
  end

  @doc """
  Builds initial state from schema defaults.
  """
  @spec defaults_from_schema(term()) :: map()
  def defaults_from_schema([]), do: %{}

  def defaults_from_schema(%Zoi.Types.Map{fields: fields}) do
    Enum.reduce(fields, %{}, fn
      {key, %Zoi.Types.Default{} = schema}, defaults ->
        {:ok, value} = Zoi.parse(schema, nil)
        Map.put(defaults, key, value)

      {_key, _schema}, defaults ->
        defaults
    end)
  end
end
