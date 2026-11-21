defmodule Jido.BehaviorTree.Tree do
  @moduledoc """
  Manages the execution and traversal of behavior trees.

  The Tree module provides a clean API for executing behavior trees.
  It handles the tick propagation through the tree structure and
  maintains the current execution state.

  ## Structure

  A behavior tree is represented as a simple tree structure where
  each node can have child nodes. The tree maintains the root node
  and provides traversal and execution capabilities.

  ## Execution Model

  Trees follow the standard behavior tree execution model:
  1. Start at the root node
  2. Traverse down to child nodes based on node type logic
  3. Execute leaf nodes (actions, conditions)
  4. Propagate results back up the tree
  5. Return final status

  ## State Management

  The tree maintains execution state through individual node states.
  This allows for stateful execution where nodes can remember their
  progress between ticks.
  """

  alias Jido.BehaviorTree.{Node, Status, Tick}

  @typedoc "A behavior tree with execution state"
  @schema Zoi.struct(
            __MODULE__,
            %{
              root: Zoi.any(description: "The root node of the behavior tree")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for this module"
  def schema, do: @schema

  @doc """
  Creates a new behavior tree with the given root node.

  ## Examples

      iex> root = %MyNode{data: "test"}
      iex> tree = Jido.BehaviorTree.Tree.new(root)
      %Jido.BehaviorTree.Tree{}

  """
  @spec new(Node.t()) :: t()
  def new(root_node) do
    %__MODULE__{root: root_node}
  end

  @doc """
  Executes a single tick of the behavior tree.

  This function traverses the tree and executes nodes according to their
  logic, returning the final status and updated tree state.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> tick = Jido.BehaviorTree.Tick.new()
      iex> {status, updated_tree} = Jido.BehaviorTree.Tree.tick(tree, tick)
      {:success, %Jido.BehaviorTree.Tree{}}

  """
  @spec tick(t(), Tick.t()) :: {Status.t(), t()}
  def tick(%__MODULE__{root: root_node} = tree, tick) do
    {status, updated_node} = Node.execute_tick(root_node, tick)
    updated_tree = %{tree | root: updated_node}
    {status, updated_tree}
  end

  @doc """
  Executes a single tick with context, returning the updated tick.

  This variant is used by `Jido.Plugin.BehaviorTree` to thread
  agent state and directives through the tree during traversal.

  Unlike `tick/2`, this function returns the updated tick which may contain
  modified agent state and accumulated directives from Action nodes.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> tick = Jido.BehaviorTree.Tick.new_with_context(blackboard, agent, [], ctx)
      iex> {status, updated_tree, updated_tick} = Jido.BehaviorTree.Tree.tick_with_context(tree, tick)

  """
  @spec tick_with_context(t(), Tick.t()) :: {Status.t(), t(), Tick.t()}
  def tick_with_context(%__MODULE__{root: root_node} = tree, tick) do
    {status, updated_node, updated_tick} = Node.execute_tick_with_context(root_node, tick)
    updated_tree = %{tree | root: updated_node}
    {status, updated_tree, updated_tick}
  end

  @doc """
  Gets the root node of the tree.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> root = Jido.BehaviorTree.Tree.root(tree)
      %MyNode{}

  """
  @spec root(t()) :: Node.t()
  def root(%__MODULE__{root: root_node}) do
    root_node
  end

  @doc """
  Replaces the root node of the tree.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(old_root)
      iex> new_tree = Jido.BehaviorTree.Tree.replace_root(tree, new_root)
      %Jido.BehaviorTree.Tree{}

  """
  @spec replace_root(t(), Node.t()) :: t()
  def replace_root(%__MODULE__{} = tree, new_root) do
    %{tree | root: new_root}
  end

  @doc """
  Halts the execution of the entire tree.

  The root node halts its children. Custom parent nodes must do the same.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> halted_tree = Jido.BehaviorTree.Tree.halt(tree)
      %Jido.BehaviorTree.Tree{}

  """
  @spec halt(t()) :: t()
  def halt(%__MODULE__{root: root_node} = tree) do
    %{tree | root: Node.execute_halt(root_node)}
  end

  @doc """
  Checks if the tree is valid (has a root node that implements Node behavior).

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(valid_node)
      iex> Jido.BehaviorTree.Tree.valid?(tree)
      true

  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{root: root_node}) do
    Node.node?(root_node)
  end

  @doc """
  Gets the depth of the tree (maximum number of levels).

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(leaf_node)
      iex> Jido.BehaviorTree.Tree.depth(tree)
      1

  """
  @spec depth(t()) :: non_neg_integer()
  def depth(%__MODULE__{root: root_node}) do
    calculate_depth(root_node)
  end

  @doc """
  Counts the total number of nodes in the tree.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> Jido.BehaviorTree.Tree.node_count(tree)
      5

  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{root: root_node}) do
    count_nodes(root_node)
  end

  @doc """
  Traverses the tree and applies a function to each node.

  The function receives the node and should return an updated node.

  ## Examples

      iex> tree = Jido.BehaviorTree.Tree.new(root_node)
      iex> updated_tree = Jido.BehaviorTree.Tree.traverse(tree, &reset_node/1)
      %Jido.BehaviorTree.Tree{}

  """
  @spec traverse(t(), (Node.t() -> Node.t())) :: t()
  def traverse(%__MODULE__{root: root_node} = tree, fun) do
    updated_root = traverse_apply(root_node, fun)
    %{tree | root: updated_root}
  end

  # Private helper functions

  # Extract children from a node
  defp get_children(node) do
    case node do
      # Composite nodes have a children field
      %{children: children} when is_list(children) -> children
      # Decorator nodes have a child field
      %{child: child} -> [child]
      # Leaf nodes have no children
      _ -> []
    end
  end

  # Update children in a node
  defp set_children(node, children) do
    case node do
      # Composite nodes - update children list
      %{children: _} ->
        %{node | children: children}

      # Decorator nodes - update single child
      %{child: _} ->
        case children do
          [child] -> %{node | child: child}
          # Should not happen, but handle gracefully
          _ -> node
        end

      # Leaf nodes - no children to update
      _ ->
        node
    end
  end

  # Calculate the maximum depth of the tree
  defp calculate_depth(node) do
    children = get_children(node)

    if Enum.empty?(children) do
      1
    else
      1 + (children |> Enum.map(&calculate_depth/1) |> Enum.max())
    end
  end

  # Count all nodes in the tree
  defp count_nodes(node) do
    children = get_children(node)
    1 + Enum.sum(Enum.map(children, &count_nodes/1))
  end

  # Apply function to all nodes in the tree
  defp traverse_apply(node, fun) do
    children = get_children(node)
    updated_children = Enum.map(children, &traverse_apply(&1, fun))
    updated_node = set_children(node, updated_children)
    fun.(updated_node)
  end
end
