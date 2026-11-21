defmodule Jido.BehaviorTree.Nodes.Failer do
  @moduledoc """
  A decorator node that always returns failure when its child completes.

  - If child returns `:success` or `:failure`, failer returns `:failure`
  - If child returns `:running`, failer returns `:running`
  - Errors are passed through unchanged

  ## Example

      failer = Failer.new(some_action)
      # Always fails even if some_action succeeds

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              child: Zoi.any(description: "The child node to wrap")
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
  Creates a new Failer node wrapping the given child.

  ## Examples

      iex> Failer.new(child_node)
      %Failer{child: child_node}

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

    result_status =
      case status do
        :success -> :failure
        :failure -> :failure
        :running -> :running
        {:error, _} = error -> error
      end

    {result_status, %{state | child: updated_child}, updated_tick}
  end

  @impl true
  def halt(%__MODULE__{child: child} = state) do
    halted_child = Node.execute_halt(child)
    %{state | child: halted_child}
  end
end
