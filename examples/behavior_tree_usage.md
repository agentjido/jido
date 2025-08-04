# Behavior Tree Example for Jido

This example demonstrates how to use behavior trees with Jido agents to create complex, hierarchical decision-making systems.

## Quick Start

```elixir
# Start an IEx session
iex -S mix

# Run the interactive demo
Jido.Demos.BehaviorTreeDemo.run_interactive_demo(5)
```

## Basic Usage

### 1. Define a Behavior Tree

```elixir
alias BehaviorTree.Node

# Create a simple behavior tree
tree = Node.sequence([
  :initialize,
  Node.select([
    :primary_task,
    :fallback_task
  ]),
  :cleanup
])
```

### 2. Start a Behavior Tree Agent

```elixir
# Start the agent with the behavior tree
{:ok, agent} = Jido.Agents.BehaviorTree.start_link(
  behavior_tree: [
    tree: tree,
    context: %{status: :ready, energy: 100}
  ]
)
```

### 3. Interact with the Agent

```elixir
# Get the current behavior
{:ok, result} = Jido.Agents.BehaviorTree.get_current_behavior(agent)
IO.inspect(result.behavior)  # :initialize

# Signal success to advance the tree
{:ok, result} = Jido.Agents.BehaviorTree.succeed(agent)
IO.inspect(result.behavior)  # :primary_task

# Signal failure to try alternatives
{:ok, result} = Jido.Agents.BehaviorTree.fail(agent)
IO.inspect(result.behavior)  # :fallback_task
```

## Advanced Example: AI Character

Here's a more complex example of an AI character with multiple behaviors:

```elixir
# Define the AI character's behavior tree
character_tree = Node.sequence([
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

# Start the character agent
{:ok, character} = Jido.Agents.BehaviorTree.start_link(
  behavior_tree: [
    tree: character_tree,
    context: %{
      health: 100,
      energy: 80,
      position: {0, 0},
      enemies_nearby: false,
      food_nearby: false
    },
    verbose: true
  ]
)

# Simulate the character's decision-making
{:ok, current} = Jido.Agents.BehaviorTree.get_current_behavior(character)
IO.puts("Character wants to: #{current.behavior}")

# The character checks health (always succeeds)
{:ok, current} = Jido.Agents.BehaviorTree.succeed(character)
IO.puts("Next action: #{current.behavior}")

# Health is good, so health check fails, moves to enemy check
{:ok, current} = Jido.Agents.BehaviorTree.fail(character)
IO.puts("Next action: #{current.behavior}")
```

## Behavior Tree Nodes

The `behavior_tree` library provides several types of nodes:

### Composite Nodes

- **Sequence**: Executes children in order, fails if any child fails
- **Select**: Tries children in order, succeeds if any child succeeds

```elixir
# Sequence: do A, then B, then C
Node.sequence([:a, :b, :c])

# Select: try A, if it fails try B, if it fails try C
Node.select([:a, :b, :c])
```

### Decorator Nodes

- **repeat_until_fail**: Repeats child until it fails
- **repeat_until_succeed**: Repeats child until it succeeds
- **repeat_n**: Repeats child N times
- **always_succeed**: Child always returns success
- **always_fail**: Child always returns failure
- **negate**: Inverts the child's result

```elixir
# Repeat an action until it fails
Node.repeat_until_fail(:keep_trying)

# Repeat exactly 3 times
Node.repeat_n(3, :do_something)

# Always succeed regardless of child outcome
Node.always_succeed(:risky_action)

# Invert the result
Node.negate(:check_condition)
```

### Random Nodes

```elixir
# Randomly pick one of the children
Node.random([:option_a, :option_b, :option_c])

# Weighted random selection
Node.random_weighted([
  {:common_action, 70},  # 70% chance
  {:rare_action, 30}     # 30% chance
])
```

## Understanding Tree Execution

Behavior trees execute by "ticking" - asking each node what it wants to do:

1. **Start**: Tree begins at the root and descends to the leftmost leaf
2. **Execute**: The current leaf behavior is returned to be executed
3. **Signal**: After execution, signal success/failure back to the tree
4. **Advance**: Tree logic determines the next behavior based on the result

```elixir
# Tree: Node.sequence([:a, :b, :c])

tree_state = BehaviorTree.start(tree)
BehaviorTree.value(tree_state)  # :a

tree_state = BehaviorTree.succeed(tree_state)  
BehaviorTree.value(tree_state)  # :b (next in sequence)

tree_state = BehaviorTree.succeed(tree_state)
BehaviorTree.value(tree_state)  # :c (next in sequence)

tree_state = BehaviorTree.succeed(tree_state)
BehaviorTree.value(tree_state)  # :a (sequence completed, restart)
```

## Context/Blackboard

The context acts as a shared memory that behaviors can read from and modify:

```elixir
# Initial context
context = %{
  health: 100,
  position: {5, 10},
  inventory: [:sword, :potion],
  last_enemy_seen: nil
}

# Behaviors can check and modify context
# For example, when simulating :attack_enemy:
if context.health > 50 do
  # Attack succeeds, but costs health
  updated_context = %{context | 
    health: context.health - 10,
    last_enemy_seen: :defeated
  }
  {:success, updated_context}
else
  # Too weak to attack
  {:failure, context}
end
```

## Integration with Jido Actions

You can create custom Jido Actions that implement specific behaviors:

```elixir
defmodule MyGame.Actions.CheckHealth do
  use Jido.Action,
    name: "check_health",
    description: "Checks character health status",
    schema: [
      context: [type: :map, required: true, doc: "Character context"]
    ]

  def run(%{context: context}) do
    health_status = cond do
      context.health > 70 -> :healthy
      context.health > 30 -> :injured  
      true -> :critical
    end
    
    updated_context = Map.put(context, :health_status, health_status)
    
    {:ok, %{
      result: health_status,
      context: updated_context
    }}
  end
end
```

## Running the Demo

The included demo shows a complete AI character simulation:

```elixir
# Run the full interactive demo
Jido.Demos.BehaviorTreeDemo.run_interactive_demo(10)

# Or control it step by step
{:ok, demo} = Jido.Demos.BehaviorTreeDemo.start()
{:ok, demo} = Jido.Demos.BehaviorTreeDemo.step(demo)
{:ok, demo} = Jido.Demos.BehaviorTreeDemo.step(demo)

# Check current state
status = Jido.Demos.BehaviorTreeDemo.get_status(demo)
IO.inspect(status)
```

This will show how the AI character makes decisions based on its behavior tree, demonstrating the power of hierarchical decision-making systems in agent architectures.
