defmodule Jido.BehaviorTree.Nodes.Selector do
  @moduledoc """
  A composite node that selects the first successful child.

  The Selector node executes each child in order until one succeeds.
  If any child succeeds, the selector succeeds immediately.
  If all children fail, the selector fails.
  If a child returns running, the selector returns running and will resume
  from that child on the next tick.

  Also known as a "fallback" or "priority" node.

  ## Example

      selector = Selector.new([
        TryOption1.new(),
        TryOption2.new(),
        FallbackOption.new()
      ])

  """

  alias Jido.BehaviorTree.Node

  @schema Zoi.struct(
            __MODULE__,
            %{
              children: Zoi.list(Zoi.any(), description: "List of child nodes to try in order"),
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
  Creates a new Selector node with the given children.

  ## Examples

      iex> Selector.new([node1, node2, node3])
      %Selector{children: [node1, node2, node3], current_index: 0}

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
    {:failure, %{state | current_index: 0}, tick}
  end

  defp execute_from_with_context(state, children, index, tick) do
    child = Enum.at(children, index)
    {status, updated_child, updated_tick} = Node.execute_tick_with_context(child, tick)
    updated_children = List.replace_at(children, index, updated_child)

    case status do
      :success ->
        {:success, %{state | children: updated_children, current_index: 0}, updated_tick}

      :failure ->
        execute_from_with_context(
          %{state | children: updated_children},
          updated_children,
          index + 1,
          updated_tick
        )

      :running ->
        {:running, %{state | children: updated_children, current_index: index}, updated_tick}

      {:error, _reason} = error ->
        {error, %{state | children: updated_children, current_index: 0}, updated_tick}
    end
  end
end
