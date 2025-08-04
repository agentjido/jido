defmodule Jido.Agents.BehaviorTree do
  @moduledoc """
  A Jido agent driven by behavior trees.
  
  This agent uses behavior trees to make decisions and execute behaviors.
  Behavior trees provide a powerful way to create complex, hierarchical
  decision-making systems that are easy to understand and modify.
  
  ## Features
  
  - Execute behavior trees with standard nodes (sequence, select, decorators)
  - Maintain shared context/blackboard between behaviors
  - Support for custom behavior implementations
  - Automatic or manual tree progression
  
  ## Example Usage
  
      # Define a simple behavior tree
      tree = BehaviorTree.Node.sequence([
        :initialize,
        BehaviorTree.Node.select([
          :primary_task,
          :fallback_task
        ]),
        :cleanup
      ])
      
      # Start the agent
      {:ok, agent} = Jido.Agents.BehaviorTree.start_link(
        behavior_tree: [
          tree: tree,
          context: %{status: :ready}
        ]
      )
      
      # Get the current behavior
      current = Jido.Agents.BehaviorTree.get_current_behavior(agent)
      
      # Signal success/failure to advance the tree
      Jido.Agents.BehaviorTree.succeed(agent)
      Jido.Agents.BehaviorTree.fail(agent)
  """
  
  use Jido.Agent,
    name: "behavior_tree_agent",
    description: "An agent driven by behavior trees",
    category: "AI Agents",
    tags: ["behavior_tree", "AI", "decision_making"],
    vsn: "0.1.0",
    actions: [
      Jido.Actions.BehaviorTree.Tick,
      Jido.Actions.BehaviorTree.Succeed,
      Jido.Actions.BehaviorTree.Fail,
      Jido.Actions.BehaviorTree.Reset,
      Jido.Actions.BehaviorTree.GetCurrent,
      Jido.Actions.StateManager.Get,
      Jido.Actions.StateManager.Set,
      Jido.Actions.StateManager.Update,
      Jido.Actions.StateManager.Delete
    ]

  @default_opts [
    skills: [Jido.Skills.BehaviorTree]
  ]

  @default_timeout Application.compile_env(:jido, :default_timeout, 30_000)

  @default_kwargs [
    timeout: @default_timeout
  ]

  @impl true
  def start_link(opts) do
    opts = Keyword.merge(@default_opts, opts)
    Jido.Agent.Server.start_link(opts)
  end

  @doc """
  Gets the current behavior from the behavior tree.
  
  Returns the current behavior that the agent should execute.
  """
  def get_current_behavior(pid, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.get_current", %{})
    
    call(pid, signal, timeout)
  end

  @doc """
  Advances the behavior tree by one tick.
  
  Returns the next behavior that the agent should execute.
  """
  def tick(pid, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.tick", %{})
    
    call(pid, signal, timeout)
  end

  @doc """
  Signals that the current behavior has succeeded.
  
  This advances the behavior tree and returns the next behavior.
  """
  def succeed(pid, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.succeed", %{})
    
    call(pid, signal, timeout)
  end

  @doc """
  Signals that the current behavior has failed.
  
  This advances the behavior tree and returns the next behavior.
  """
  def fail(pid, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.fail", %{})
    
    call(pid, signal, timeout)
  end

  @doc """
  Resets the behavior tree to its initial state.
  
  Returns the initial behavior of the tree.
  """
  def reset(pid, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.reset", %{})
    
    call(pid, signal, timeout)
  end

  @doc """
  Updates the context/blackboard for the behavior tree.
  
  The context is shared state that behaviors can read from and write to.
  """
  def update_context(pid, new_context, kwargs \\ @default_kwargs) do
    timeout = Keyword.get(kwargs, :timeout, @default_timeout)
    {:ok, signal} = build_signal("jido.bt.update_context", %{context: new_context})
    
    call(pid, signal, timeout)
  end

  defp build_signal(type, data) do
    Jido.Signal.new(%{
      type: type,
      data: data
    })
  end
end
