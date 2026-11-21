defmodule Jido.BehaviorTree do
  @moduledoc """
  Behavior Tree implementation for Jido agents with integrated action support.

  This module provides a comprehensive behavior tree system that integrates
  seamlessly with the Jido action framework. Behavior trees are a powerful
  control structure for AI systems, allowing complex decision-making logic
  to be composed from simple, reusable components.

  ## Features

  - **Composable Nodes**: Build complex behaviors from simple building blocks
  - **Jido Action Integration**: Execute Jido actions directly in behavior tree nodes
  - **Tick-based Execution**: Standard behavior tree execution model
  - **Blackboard Pattern**: Shared state management across tree nodes
  - **Telemetry Support**: Built-in instrumentation for monitoring and debugging
  - **AI Tool Compatible**: Convert behavior trees to AI-compatible tool definitions

  ## Quick Start

      # Define a simple behavior tree
      tree =
        Jido.BehaviorTree.Tree.new(
          Jido.BehaviorTree.Nodes.Sequence.new([
            Jido.BehaviorTree.Nodes.Action.new(MyAction, %{input: "test"}),
            Jido.BehaviorTree.Nodes.Action.new(AnotherAction, %{})
          ])
        )

      # Execute the tree
      {:ok, agent} = Jido.BehaviorTree.Agent.start_link(tree: tree)
      status = Jido.BehaviorTree.Agent.tick(agent)

  ## Core Concepts

  ### Status

  Every node in a behavior tree returns one of these statuses:
  - `:success` - The node completed successfully
  - `:failure` - The node failed to complete
  - `:running` - The node is still executing
  - `{:error, reason}` - The node encountered an execution error

  ### Nodes

  Behavior trees are composed of three types of nodes:
  - **Composite Nodes**: Control the execution of child nodes (Sequence, Selector)
  - **Decorator Nodes**: Modify the behavior of a single child node (Inverter, Succeeder, Failer, Repeat)
  - **Leaf Nodes**: Perform actual work (Action, Wait, SetBlackboard)

  ### Blackboard

  The blackboard is a shared data structure that nodes can read from and write to,
  enabling communication between different parts of the tree.

  ## AI Integration

  Behavior trees can be converted to AI-compatible tool definitions:

      skill = Jido.BehaviorTree.Skill.new("user_registration", tree, "Registers a new user")
      tool_def = Jido.BehaviorTree.Skill.to_tool(skill)

  This allows LLMs to execute behavior trees as function calls.
  """

  alias Jido.BehaviorTree.{Blackboard, Node, Skill, Status, Tick, Tree}

  @doc """
  Creates a new behavior tree with the given root node.

  ## Examples

      iex> root = Jido.BehaviorTree.Nodes.Wait.new(1)
      iex> tree = Jido.BehaviorTree.new(root)
      iex> %Jido.BehaviorTree.Tree{root: %Jido.BehaviorTree.Nodes.Wait{duration_ms: 1}} = tree
      %Jido.BehaviorTree.Tree{root: %Jido.BehaviorTree.Nodes.Wait{duration_ms: 1, start_time: nil}}

  """
  @spec new(Node.t()) :: Tree.t()
  def new(root_node) do
    Tree.new(root_node)
  end

  @doc """
  Executes a single tick of the behavior tree.

  This function traverses the tree and executes nodes according to their
  logic, returning the final status and updated tree state.
  """
  @spec tick(Tree.t(), Tick.t()) :: {Status.t(), Tree.t()}
  def tick(tree, tick) do
    Tree.tick(tree, tick)
  end

  @doc """
  Creates a new blackboard with optional initial data.
  """
  @spec blackboard(map()) :: Blackboard.t()
  def blackboard(initial_data \\ %{}) do
    Blackboard.new(initial_data)
  end

  @doc """
  Creates a new tick with optional blackboard and timestamp.
  """
  @spec tick() :: Tick.t()
  @spec tick(Blackboard.t()) :: Tick.t()
  def tick(blackboard \\ Blackboard.new()) do
    Tick.new(blackboard)
  end

  @doc """
  Starts a behavior tree agent with the given options.

  ## Options

  - `:tree` - The behavior tree to execute (required)
  - `:blackboard` - Initial blackboard data (default: empty)
  - `:mode` - Execution mode, either `:manual` or `:auto` (default: `:manual`)
  - `:interval` - Tick interval in milliseconds for auto mode (default: 1000)
  """
  @spec start_agent(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_agent(opts) do
    Jido.BehaviorTree.Agent.start_link(opts)
  end

  @doc """
  Creates a behavior tree skill for AI integration.
  """
  @spec skill(String.t(), Tree.t(), String.t(), keyword()) :: Skill.t()
  def skill(name, tree, description \\ "", opts \\ []) do
    Jido.BehaviorTree.Skill.new(name, tree, description, opts)
  end
end
