defmodule Jido.BehaviorTree.Nodes.Named do
  @moduledoc false

  alias Jido.BehaviorTree.Node

  @behaviour Node
  @enforce_keys [:child, :node_path]
  defstruct [:child, :node_path]

  @spec new(Node.t(), [atom()]) :: %__MODULE__{}
  def new(child, path), do: %__MODULE__{child: child, node_path: path}

  @impl true
  def tick(node, tick) do
    {status, child} = Node.execute_tick(node.child, tick)
    {status, %{node | child: child}}
  end

  @impl true
  def tick_with_context(node, tick) do
    {status, child, tick} = Node.execute_tick_with_context(node.child, tick)
    {status, %{node | child: child}, tick}
  end

  @impl true
  def halt(node), do: %{node | child: Node.execute_halt(node.child)}
end
