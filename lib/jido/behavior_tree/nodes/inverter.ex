defmodule Jido.BehaviorTree.Nodes.Inverter do
  @moduledoc """
  A decorator node that inverts the result of its child.

  The Inverter node wraps a single child node and inverts the final status:
  - If the child succeeds, the inverter fails
  - If the child fails, the inverter succeeds
  - Running and error statuses are passed through unchanged

  ## Example

      inverter = Inverter.new(CheckEnemyNearby.new())
      # Returns :success when CheckEnemyNearby returns :failure
      # Returns :failure when CheckEnemyNearby returns :success

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              child: Zoi.any(description: "The child node to invert")
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
  Creates a new Inverter node wrapping the given child.

  ## Examples

      iex> Inverter.new(child_node)
      %Inverter{child: child_node}

  """
  @spec new(Node.t()) :: t()
  def new(child) do
    %__MODULE__{child: child}
  end

  @impl true
  def tick(state, tick) do
    {status, state, _tick} = tick_with_context(state, tick)
    {status, state}
  end

  @doc """
  Context-aware tick that preserves child tick mutations.
  """
  @impl true
  @spec tick_with_context(t(), Jido.BehaviorTree.Tick.t()) ::
          {Jido.BehaviorTree.Status.t(), t(), Jido.BehaviorTree.Tick.t()}
  def tick_with_context(%__MODULE__{child: child} = state, tick) do
    {status, updated_child, updated_tick} = Node.execute_tick_with_context(child, tick)

    inverted_status =
      case status do
        :success -> :failure
        :failure -> :success
        other -> other
      end

    {inverted_status, %{state | child: updated_child}, updated_tick}
  end

  @impl true
  def halt(%__MODULE__{child: child} = state) do
    halted_child = Node.execute_halt(child)
    %{state | child: halted_child}
  end
end
