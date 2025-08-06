defmodule Jido.Actions.BehaviorTree do
  @moduledoc """
  Actions for managing behavior trees in Jido agents.
  
  These actions provide the core functionality for behavior tree operations:
  - Ticking the tree to advance state
  - Signaling success/failure outcomes
  - Resetting the tree
  - Getting the current behavior
  """
end

defmodule Jido.Actions.BehaviorTree.Tick do
  @moduledoc """
  Advances the behavior tree by one step and returns the current behavior.
  
  This action is typically called to get the next behavior that the agent
  should execute. The behavior tree maintains its internal state between
  ticks.
  """
  
  use Jido.Action,
    name: "behavior_tree_tick",
    description: "Advances the behavior tree and returns the current behavior",
    schema: [
      tree: [type: :any, required: true, doc: "The behavior tree structure"],
      context: [type: :map, default: %{}, doc: "The shared context/blackboard"],
      verbose: [type: :boolean, default: false, doc: "Enable verbose logging"]
    ]

  alias BehaviorTree
  require Logger

  def run(%{tree: tree_node, context: context, verbose: verbose}, action_context) do
    # Start or continue the behavior tree
    behavior_tree = BehaviorTree.start(tree_node)
    current_behavior = BehaviorTree.value(behavior_tree)
    
    if verbose do
      Logger.info("BehaviorTree.Tick: Current behavior is #{inspect(current_behavior)}")
    end
    
    # Create new state with updated tree state and context
    new_state = Map.merge(action_context.state, %{
      tree_state: behavior_tree,
      context: context
    })
    
    # Replace the entire state
    state_directives = [
      %Jido.Agent.Directive.StateModification{
        op: :replace,
        path: [],
        value: new_state
      }
    ]
    
    {:ok, %{
      behavior: current_behavior,
      tree_state: behavior_tree,
      context: context
    }, state_directives}
  end
end

defmodule Jido.Actions.BehaviorTree.Succeed do
  @moduledoc """
  Signals that the current behavior has succeeded.
  
  This advances the behavior tree by marking the current behavior as successful
  and determining the next behavior to execute.
  """
  
  use Jido.Action,
    name: "behavior_tree_succeed",
    description: "Signals that the current behavior succeeded",
    schema: [
      tree_state: [type: :any, required: false, doc: "The current behavior tree state (optional, reads from agent state if not provided)"],
      context: [type: :map, default: %{}, doc: "The shared context/blackboard"],
      verbose: [type: :boolean, default: false, doc: "Enable verbose logging"]
    ]

  alias BehaviorTree
  require Logger

  def run(params, context) do
    verbose = Map.get(params, :verbose, false)
    
    # Try to get tree_state from params, otherwise use agent state
    {tree_state, bt_context} = case Map.get(params, :tree_state) do
      nil ->
        # Get from agent state
        agent_state = context.state
        tree_state = agent_state.tree_state || BehaviorTree.start(agent_state.tree)
        bt_context = agent_state.context
        {tree_state, bt_context}
      
      provided_tree_state ->
        bt_context = Map.get(params, :context, %{})
        {provided_tree_state, bt_context}
    end
    
    new_tree_state = BehaviorTree.succeed(tree_state)
    current_behavior = BehaviorTree.value(new_tree_state)
    
    if verbose do
      Logger.info("BehaviorTree.Succeed: Advanced to behavior #{inspect(current_behavior)}")
    end
    
    # Create new state with updated tree state and context
    new_state = Map.merge(context.state, %{
      tree_state: new_tree_state,
      context: bt_context
    })
    
    # Replace the entire state
    state_directives = [
      %Jido.Agent.Directive.StateModification{
        op: :replace,
        path: [],
        value: new_state
      }
    ]
    
    {:ok, %{
      behavior: current_behavior,
      tree_state: new_tree_state,
      context: bt_context
    }, state_directives}
  end
end

defmodule Jido.Actions.BehaviorTree.Fail do
  @moduledoc """
  Signals that the current behavior has failed.
  
  This advances the behavior tree by marking the current behavior as failed
  and determining the next behavior to execute.
  """
  
  use Jido.Action,
    name: "behavior_tree_fail",
    description: "Signals that the current behavior failed",
    schema: [
      tree_state: [type: :any, required: false, doc: "The current behavior tree state (optional, reads from agent state if not provided)"],
      context: [type: :map, default: %{}, doc: "The shared context/blackboard"],
      verbose: [type: :boolean, default: false, doc: "Enable verbose logging"]
    ]

  alias BehaviorTree
  require Logger

  def run(params, context) do
    verbose = Map.get(params, :verbose, false)
    
    # Try to get tree_state from params, otherwise use agent state
    {tree_state, bt_context} = case Map.get(params, :tree_state) do
      nil ->
        # Get from agent state
        agent_state = context.state
        tree_state = agent_state.tree_state || BehaviorTree.start(agent_state.tree)
        bt_context = agent_state.context
        {tree_state, bt_context}
      
      provided_tree_state ->
        bt_context = Map.get(params, :context, %{})
        {provided_tree_state, bt_context}
    end
    
    new_tree_state = BehaviorTree.fail(tree_state)
    current_behavior = BehaviorTree.value(new_tree_state)
    
    if verbose do
      Logger.info("BehaviorTree.Fail: Advanced to behavior #{inspect(current_behavior)}")
    end
    
    # Create new state with updated tree state and context
    new_state = Map.merge(context.state, %{
      tree_state: new_tree_state,
      context: bt_context
    })
    
    # Replace the entire state
    state_directives = [
      %Jido.Agent.Directive.StateModification{
        op: :replace,
        path: [],
        value: new_state
      }
    ]
    
    {:ok, %{
      behavior: current_behavior,
      tree_state: new_tree_state,
      context: bt_context
    }, state_directives}
  end
end

defmodule Jido.Actions.BehaviorTree.Reset do
  @moduledoc """
  Resets the behavior tree to its initial state.
  
  This is useful when you want to restart the behavior tree from the beginning,
  perhaps after completing a goal or encountering an error.
  """
  
  use Jido.Action,
    name: "behavior_tree_reset",
    description: "Resets the behavior tree to its initial state",
    schema: [
      tree: [type: :any, required: true, doc: "The behavior tree structure"],
      context: [type: :map, default: %{}, doc: "The shared context/blackboard"],
      verbose: [type: :boolean, default: false, doc: "Enable verbose logging"]
    ]

  alias BehaviorTree
  require Logger

  def run(%{tree: tree_node, context: context, verbose: verbose}, action_context) do
    behavior_tree = BehaviorTree.start(tree_node)
    current_behavior = BehaviorTree.value(behavior_tree)
    
    if verbose do
      Logger.info("BehaviorTree.Reset: Reset to behavior #{inspect(current_behavior)}")
    end
    
    # Create new state with reset tree state and context
    new_state = Map.merge(action_context.state, %{
      tree_state: behavior_tree,
      context: context
    })
    
    # Replace the entire state
    state_directives = [
      %Jido.Agent.Directive.StateModification{
        op: :replace,
        path: [],
        value: new_state
      }
    ]
    
    {:ok, %{
      behavior: current_behavior,
      tree_state: behavior_tree,
      context: context
    }, state_directives}
  end
end

defmodule Jido.Actions.BehaviorTree.GetCurrent do
  @moduledoc """
  Gets the current behavior from the behavior tree without advancing it.
  
  This is useful for checking what the agent should be doing without
  changing the tree's state.
  """
  
  use Jido.Action,
    name: "behavior_tree_get_current",
    description: "Gets the current behavior without advancing the tree",
    schema: [
      tree_state: [type: :any, required: false, doc: "The current behavior tree state (optional, reads from agent state if not provided)"],
      context: [type: :map, default: %{}, doc: "The shared context/blackboard"],
      verbose: [type: :boolean, default: false, doc: "Enable verbose logging"]
    ]

  alias BehaviorTree
  require Logger

  def run(params, context) do
    verbose = Map.get(params, :verbose, false)
    
    # Try to get tree_state from params, otherwise use agent state
    {tree_state, bt_context} = case Map.get(params, :tree_state) do
      nil ->
        # Get from agent state
        agent_state = context.state
        tree_state = agent_state.tree_state || BehaviorTree.start(agent_state.tree)
        bt_context = agent_state.context
        {tree_state, bt_context}
      
      provided_tree_state ->
        bt_context = Map.get(params, :context, %{})
        {provided_tree_state, bt_context}
    end
    
    current_behavior = BehaviorTree.value(tree_state)
    
    if verbose do
      Logger.info("BehaviorTree.GetCurrent: Current behavior is #{inspect(current_behavior)}")
    end
    
    {:ok, %{
      behavior: current_behavior,
      tree_state: tree_state,
      context: bt_context
    }}
  end
end
