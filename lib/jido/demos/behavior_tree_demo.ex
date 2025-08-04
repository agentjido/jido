defmodule Jido.Demos.BehaviorTreeDemo do
  @moduledoc """
  A demo implementation showing how to use behavior trees with Jido agents.
  
  This demo creates a simple AI character that follows a behavior tree to:
  1. Check its health
  2. Either attack enemies, find food, or wander around
  3. Rest when needed
  
  ## Usage
  
      # Start the demo
      {:ok, demo} = Jido.Demos.BehaviorTreeDemo.start()
      
      # Run a few steps
      Jido.Demos.BehaviorTreeDemo.step(demo)
      Jido.Demos.BehaviorTreeDemo.step(demo)
      
      # Simulate different outcomes
      Jido.Demos.BehaviorTreeDemo.simulate_success(demo)
      Jido.Demos.BehaviorTreeDemo.simulate_failure(demo)
      
      # Check current state
      Jido.Demos.BehaviorTreeDemo.get_status(demo)
  """
  
  alias BehaviorTree.Node
  alias Jido.Agents.BehaviorTree, as: BTAgent
  require Logger

  defstruct [:agent_pid, :step_count]

  @doc """
  Starts a new behavior tree demo.
  
  Creates an agent with a predefined behavior tree that simulates
  a simple AI character making decisions.
  """
  def start(opts \\ []) do
    # Define the behavior tree structure
    tree = build_demo_tree()
    
    # Initial context (the "blackboard")
    initial_context = %{
      health: 100,
      energy: 80,
      position: {0, 0},
      enemies_nearby: false,
      food_nearby: false,
      last_action: nil
    }
    
    # Create the agent with initial state
    initial_state = %{
      tree: tree,
      context: initial_context,
      tree_state: nil,
      verbose: Keyword.get(opts, :verbose, true)
    }
    
    agent = BTAgent.new(nil, initial_state)
    
    # Start the behavior tree agent
    agent_opts = [
      agent: agent,
      skills: [Jido.Skills.BehaviorTree, Jido.Skills.StateManager],
      behavior_tree: [
        tree: tree,
        context: initial_context,
        verbose: Keyword.get(opts, :verbose, true)
      ]
    ]
    
    case Jido.Agent.Server.start_link(agent_opts) do
      {:ok, agent_pid} ->
        demo = %__MODULE__{
          agent_pid: agent_pid,
          step_count: 0
        }
        
        # Get initial behavior
        {:ok, initial_result} = BTAgent.tick(agent_pid)
        Logger.info("Demo started! Initial behavior: #{inspect(initial_result.behavior)}")
        
        {:ok, demo}
        
      error ->
        error
    end
  end

  @doc """
  Executes one step of the behavior tree demo.
  
  This simulates the agent executing its current behavior and
  progressing to the next one based on the outcome.
  """
  def step(demo) do
    {:ok, current_result} = BTAgent.get_current_behavior(demo.agent_pid)
    current_behavior = current_result.behavior
    
    Logger.info("Step #{demo.step_count + 1}: Executing behavior #{inspect(current_behavior)}")
    
    # Get current context from agent state
    {:ok, context_result} = Jido.Agent.Server.call(demo.agent_pid, %Jido.Signal{
      id: "get_context",
      type: "jido.state.get",
      data: %{path: [:context]},
      source: "demo"
    })
    current_context = context_result.value
    
    # Simulate executing the behavior and determine outcome
    {outcome, updated_context} = simulate_behavior(current_behavior, current_context)
    
    # Update context in agent state
    {:ok, _} = Jido.Agent.Server.call(demo.agent_pid, %Jido.Signal{
      id: "update_context",
      type: "jido.state.set",
      data: %{path: [:context], value: updated_context},
      source: "demo"
    })
    
    # Advance the tree based on the outcome
    next_result = case outcome do
      :success ->
        Logger.info("Behavior succeeded!")
        {:ok, result} = BTAgent.succeed(demo.agent_pid)
        result
        
      :failure ->
        Logger.info("Behavior failed!")
        {:ok, result} = BTAgent.fail(demo.agent_pid)
        result
    end
    
    Logger.info("Next behavior: #{inspect(next_result.behavior)}")
    
    {:ok, %{demo | step_count: demo.step_count + 1}}
  end

  @doc """
  Simulates a successful outcome for the current behavior.
  """
  def simulate_success(demo) do
    {:ok, result} = BTAgent.succeed(demo.agent_pid)
    Logger.info("Simulated success! Next behavior: #{inspect(result.behavior)}")
    {:ok, demo}
  end

  @doc """
  Simulates a failed outcome for the current behavior.
  """
  def simulate_failure(demo) do
    {:ok, result} = BTAgent.fail(demo.agent_pid)
    Logger.info("Simulated failure! Next behavior: #{inspect(result.behavior)}")
    {:ok, demo}
  end

  @doc """
  Gets the current status of the demo.
  """
  def get_status(demo) do
    {:ok, current_result} = BTAgent.get_current_behavior(demo.agent_pid)
    
    # Get current context and tree_state from agent
    {:ok, context_result} = Jido.Agent.Server.call(demo.agent_pid, %Jido.Signal{
      id: "get_context",
      type: "jido.state.get",
      data: %{path: [:context]},
      source: "demo"
    })
    
    {:ok, tree_state_result} = Jido.Agent.Server.call(demo.agent_pid, %Jido.Signal{
      id: "get_tree_state",
      type: "jido.state.get",
      data: %{path: [:tree_state]},
      source: "demo"
    })
    
    %{
      current_behavior: current_result.behavior,
      context: context_result.value,
      step_count: demo.step_count,
      tree_state: tree_state_result.value
    }
  end

  @doc """
  Resets the demo to its initial state.
  """
  def reset(demo) do
    {:ok, result} = BTAgent.reset(demo.agent_pid)
    Logger.info("Demo reset! Initial behavior: #{inspect(result.behavior)}")
    
    initial_context = %{
      health: 100,
      energy: 80,
      position: {0, 0},
      enemies_nearby: false,
      food_nearby: false,
      last_action: nil
    }
    
    # Reset context in agent state
    {:ok, _} = Jido.Agent.Server.call(demo.agent_pid, %Jido.Signal{
      id: "reset_context",
      type: "jido.state.set",
      data: %{path: [:context], value: initial_context},
      source: "demo"
    })
    
    {:ok, %{demo | step_count: 0}}
  end

  # Private functions

  defp build_demo_tree do
    # Main behavior sequence
    Node.sequence([
      # Always check health first
      :check_health,
      
      # Main decision tree
      Node.select([
        # If health is low, prioritize finding food
        Node.sequence([
          :is_health_low,
          :find_food
        ]),
        
        # If enemies nearby, decide whether to fight or flee
        Node.sequence([
          :check_for_enemies,
          Node.select([
            :attack_enemy,
            :flee_from_enemy
          ])
        ]),
        
        # If food nearby, go eat
        Node.sequence([
          :check_for_food,
          :eat_food
        ]),
        
        # Default behaviors
        Node.select([
          :explore,
          :rest,
          :wander
        ])
      ])
    ])
  end

  defp simulate_behavior(behavior, context) do
    case behavior do
      :check_health ->
        # Always succeeds, updates context with health status
        health_status = cond do
          context.health > 70 -> :healthy
          context.health > 30 -> :injured
          true -> :critical
        end
        
        updated_context = Map.put(context, :health_status, health_status)
        {:success, updated_context}

      :is_health_low ->
        # Succeeds if health is below 50
        if context.health < 50 do
          {:success, context}
        else
          {:failure, context}
        end

      :check_for_enemies ->
        # Randomly determine if enemies are nearby
        enemies_nearby = :rand.uniform() < 0.3  # 30% chance
        updated_context = Map.put(context, :enemies_nearby, enemies_nearby)
        
        if enemies_nearby do
          {:success, updated_context}
        else
          {:failure, updated_context}
        end

      :check_for_food ->
        # Randomly determine if food is nearby
        food_nearby = :rand.uniform() < 0.4  # 40% chance
        updated_context = Map.put(context, :food_nearby, food_nearby)
        
        if food_nearby do
          {:success, updated_context}
        else
          {:failure, updated_context}
        end

      :attack_enemy ->
        # Success depends on health and energy
        success_chance = if context.health > 50 and context.energy > 30, do: 0.7, else: 0.3
        
        if :rand.uniform() < success_chance do
          updated_context = context
          |> Map.put(:health, max(0, context.health - 10))
          |> Map.put(:energy, max(0, context.energy - 20))
          |> Map.put(:last_action, :attack)
          {:success, updated_context}
        else
          updated_context = context
          |> Map.put(:health, max(0, context.health - 20))
          |> Map.put(:energy, max(0, context.energy - 10))
          |> Map.put(:last_action, :failed_attack)
          {:failure, updated_context}
        end

      :flee_from_enemy ->
        # Usually succeeds but costs energy
        {x, y} = context.position
        updated_context = context
        |> Map.put(:energy, max(0, context.energy - 15))
        |> Map.put(:position, {x + 1, y})
        |> Map.put(:last_action, :flee)
        {:success, updated_context}

      :find_food ->
        # Takes time and energy, moderate success rate
        if :rand.uniform() < 0.6 do
          updated_context = context
          |> Map.put(:food_nearby, true)
          |> Map.put(:energy, max(0, context.energy - 5))
          |> Map.put(:last_action, :found_food)
          {:success, updated_context}
        else
          updated_context = context
          |> Map.put(:energy, max(0, context.energy - 10))
          |> Map.put(:last_action, :search_failed)
          {:failure, updated_context}
        end

      :eat_food ->
        # Always succeeds if food is nearby
        if context.food_nearby do
          updated_context = context
          |> Map.put(:health, min(100, context.health + 20))
          |> Map.put(:energy, min(100, context.energy + 15))
          |> Map.put(:food_nearby, false)
          |> Map.put(:last_action, :ate_food)
          {:success, updated_context}
        else
          {:failure, context}
        end

      :explore ->
        # Moderate success, costs energy
        if :rand.uniform() < 0.5 do
          {x, y} = context.position
          updated_context = context
          |> Map.put(:energy, max(0, context.energy - 5))
          |> Map.put(:position, {x + 1, y + 1})
          |> Map.put(:last_action, :explored)
          {:success, updated_context}
        else
          updated_context = Map.put(context, :last_action, :lost)
          {:failure, updated_context}
        end

      :rest ->
        # Always succeeds, restores energy
        updated_context = context
        |> Map.put(:energy, min(100, context.energy + 25))
        |> Map.put(:last_action, :rested)
        {:success, updated_context}

      :wander ->
        # Always succeeds, slight energy cost
        {x, y} = context.position
        new_position = {x + (:rand.uniform(3) - 2), y + (:rand.uniform(3) - 2)}
        
        updated_context = context
        |> Map.put(:position, new_position)
        |> Map.put(:energy, max(0, context.energy - 2))
        |> Map.put(:last_action, :wandered)
        {:success, updated_context}

      _ ->
        # Unknown behavior
        {:failure, context}
    end
  end

  @doc """
  Runs an interactive demo session.
  
  This runs the demo for a specified number of steps, showing
  how the behavior tree guides the agent's decisions.
  """
  def run_interactive_demo(steps \\ 10) do
    Logger.info("Starting Behavior Tree Demo...")
    
    {:ok, demo} = start(verbose: true)
    
    Enum.reduce(1..steps, demo, fn step_num, current_demo ->
      Logger.info("\n=== STEP #{step_num} ===")
      
      # Show current status
      status = get_status(current_demo)
      Logger.info("Context: #{inspect(status.context)}")
      Logger.info("Current behavior: #{inspect(status.current_behavior)}")
      
      # Execute the step
      {:ok, updated_demo} = step(current_demo)
      
      # Small delay for readability
      Process.sleep(1000)
      
      updated_demo
    end)
    
    Logger.info("\nDemo completed!")
  end
end
