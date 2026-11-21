defmodule Jido.BehaviorTree.Nodes.Sequence do
  @moduledoc """
  A composite node that executes children in sequence.

  The Sequence node executes each child in order. If all children succeed,
  the sequence succeeds. If any child fails, the sequence fails immediately.
  If a child returns running, the sequence returns running and will resume
  from that child on the next tick.

  ## Example

      sequence = Sequence.new([
        CheckCondition.new(),
        PerformAction.new(),
        LogResult.new()
      ])

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              children: Zoi.list(Zoi.any(), description: "List of child nodes to execute in order"),
              current_index:
                Zoi.integer(description: "Index of currently executing child")
                |> Zoi.min(0)
                |> Zoi.default(0)
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
  Creates a new Sequence node with the given children.

  ## Examples

      iex> Sequence.new([node1, node2, node3])
      %Sequence{children: [node1, node2, node3], current_index: 0}

  """
  @spec new(list(Node.t())) :: t()
  def new(children) when is_list(children) do
    %__MODULE__{children: children, current_index: 0}
  end

  @impl true
  def tick(state, tick) do
    {status, state, _tick} = tick_with_context(state, tick)
    {status, state}
  end

  @doc """
  Context-aware tick that threads the tick through child nodes.

  Used by `Tree.tick_with_context/2` to ensure agent state and directives
  are properly accumulated as children execute.
  """
  @impl true
  @spec tick_with_context(t(), Jido.BehaviorTree.Tick.t()) ::
          {Jido.BehaviorTree.Status.t(), t(), Jido.BehaviorTree.Tick.t()}
  def tick_with_context(%__MODULE__{children: children, current_index: index} = state, tick) do
    execute_from_with_context(state, children, index, tick)
  end

  @impl true
  def halt(%__MODULE__{children: children} = state) do
    halted_children = Enum.map(children, &Node.execute_halt/1)
    %{state | children: halted_children, current_index: 0}
  end

  defp execute_from_with_context(state, children, index, tick) when index >= length(children) do
    {:success, %{state | current_index: 0}, tick}
  end

  defp execute_from_with_context(state, children, index, tick) do
    child = Enum.at(children, index)
    {status, updated_child, updated_tick} = Node.execute_tick_with_context(child, tick)
    updated_children = List.replace_at(children, index, updated_child)

    case status do
      :success ->
        execute_from_with_context(
          %{state | children: updated_children},
          updated_children,
          index + 1,
          updated_tick
        )

      :failure ->
        {:failure, %{state | children: updated_children, current_index: 0}, updated_tick}

      :running ->
        {:running, %{state | children: updated_children, current_index: index}, updated_tick}

      {:error, _reason} = error ->
        {error, %{state | children: updated_children, current_index: 0}, updated_tick}
    end
  end
end
