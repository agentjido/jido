defmodule Jido.BehaviorTree.Nodes.SetBlackboard do
  @moduledoc """
  A leaf node that sets values in the blackboard.

  Always returns `:success` after setting the specified key-value pairs.
  Note: Since ticks are immutable, the updated blackboard is returned
  in the node state for the parent to propagate.

  ## Example

      node = SetBlackboard.new(:player_health, 100)
      # Sets :player_health to 100 in the blackboard

      node = SetBlackboard.new(%{a: 1, b: 2})
      # Sets multiple values at once

  """

  alias Jido.BehaviorTree.Tick

  @schema Zoi.struct(
            __MODULE__,
            %{
              entries:
                Zoi.map(Zoi.atom(), Zoi.any(), description: "Key-value pairs to set in blackboard")
                |> Zoi.default(%{}),
              updated_tick: Zoi.any(description: "The tick with updated blackboard") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @behaviour Jido.BehaviorTree.Node

  @doc """
  Creates a new SetBlackboard node with the specified entries.

  ## Examples

      iex> SetBlackboard.new(%{key: "value"})
      %SetBlackboard{entries: %{key: "value"}, updated_tick: nil}

      iex> SetBlackboard.new(:key, "value")
      %SetBlackboard{entries: %{key: "value"}, updated_tick: nil}

  """
  @spec new(map()) :: t()
  def new(entries) when is_map(entries) do
    %__MODULE__{entries: entries, updated_tick: nil}
  end

  @spec new(atom(), term()) :: t()
  def new(key, value) when is_atom(key) do
    %__MODULE__{entries: %{key => value}, updated_tick: nil}
  end

  @impl true
  def tick(state, tick) do
    {status, state, _tick} = tick_with_context(state, tick)
    {status, state}
  end

  @doc """
  Context-aware tick variant that returns the updated tick.
  """
  @impl true
  @spec tick_with_context(t(), Tick.t()) ::
          {Jido.BehaviorTree.Status.t(), t(), Tick.t()}
  def tick_with_context(%__MODULE__{entries: entries} = state, tick) do
    updated_tick = apply_entries(entries, tick)
    {:success, %{state | updated_tick: updated_tick}, updated_tick}
  end

  @impl true
  def halt(state) do
    %{state | updated_tick: nil}
  end

  defp apply_entries(entries, tick) do
    Enum.reduce(entries, tick, fn {key, value}, acc ->
      Tick.put(acc, key, value)
    end)
  end
end
