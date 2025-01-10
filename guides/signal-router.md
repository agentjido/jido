# Signal Router

In our previous guides, we explored how Signals provide real-time event streams and how the Signal Bus enables message distribution. Now, let's discover how the Signal Router enables sophisticated message routing using Instructions in your Jido system.

## Understanding the Router

The Signal Router is a powerful trie-based message routing system that:
- Routes signals to appropriate Instructions based on path patterns
- Supports both wildcards and pattern matching functions
- Manages execution priority and complexity-based ordering 
- Provides efficient trie-based path matching
- Integrates with Jido's Instruction system

Think of the Router as a smart traffic controller for your signals - it ensures each signal reaches its intended handlers in the correct order, supporting both simple path matching and complex routing rules.

## Core Concepts

Before diving into code, let's understand the key concepts:

### Routes
A route connects a signal path pattern to one or more Instructions. Routes support:
- Exact matches: `"user.created"`
- Single-level wildcards: `"user.*.updated"`
- Multi-level wildcards: `"order.**.completed"`

### Instructions
Instructions wrapped in routes:
- Define an Action module to execute
- Can have priorities (-100 to 100)
- May include pattern matching functions
- Integrate with Jido's execution system

### Priority & Complexity
Handlers execute based on:
- Priority (higher numbers execute first)
- Path complexity scoring
- Registration order for same priority/complexity

## Creating Your First Router

Let's create a router to handle user-related signals:

```elixir
# Define some actions
defmodule MyApp.Actions.AuditUser do
  use Jido.Action,
    name: "audit_user",
    description: "Logs user events for auditing",
    schema: [
      signal: [type: :map, required: true]
    ]

  def run(%{signal: signal}, _context) do
    Logger.info("User event: #{signal.type}")
    {:ok, :audited}
  end
end

defmodule MyApp.Actions.HandlePremiumUser do
  use Jido.Action,
    name: "handle_premium_user", 
    schema: [
      signal: [type: :map, required: true]
    ]

  def run(%{signal: signal}, _context) do
    if signal.data.premium do
      Process.send(PremiumWorker, {:process, signal}, [])
      {:ok, :premium_queued}
    else
      {:ok, :ignored}
    end
  end
end

# Create a router with multiple routes
{:ok, router} = Jido.Signal.Router.new([
  # High priority audit logging
  {"user.**", %Instruction{
    action: MyApp.Actions.AuditUser
  }, 100},
  
  # Pattern match for premium users
  {"user.*.updated",
    fn signal -> Map.get(signal.data, :premium, false) end,
    %Instruction{
      action: MyApp.Actions.HandlePremiumUser
    },
    75},
   
  # Standard notification handling  
  {"user.*.notify", %Instruction{
    action: MyApp.Actions.NotifyUser
  }}
])
```

Let's break down what's happening:

1. We define Actions that handle different aspects of user signals
2. We create a router with multiple routes using different patterns
3. Each route specifies:
   - A path pattern
   - An optional pattern matching function
   - An Instruction to execute
   - An optional priority

## Route Types

The router supports several route specifications:

### 1. Basic Route with Instruction
```elixir
# Simple path and instruction
{"user.created", %Instruction{
  action: MyApp.Actions.HandleUserCreated
}}

# With priority (-100 to 100)
{"user.created", %Instruction{
  action: MyApp.Actions.HandleUserCreated
}, 90}
```

### 2. Pattern Matching Routes
```elixir
# With match function
{
  "payment.processed",
  fn signal -> signal.data.amount > 1000 end,
  %Instruction{
    action: MyApp.Actions.HandleLargePayment
  }
}

# With match and priority
{
  "payment.processed",
  fn signal -> signal.data.amount > 1000 end,
  %Instruction{
    action: MyApp.Actions.HandleLargePayment
  },
  90
}
```

### 3. Route Structs
For maximum control:
```elixir
%Route{
  path: "user.created",
  instruction: %Instruction{
    action: MyApp.Actions.HandleUserCreated
  },
  priority: 90,
  match: &MyModule.match_premium/1
}
```

## Path Matching Rules

The router implements sophisticated path matching:

### 1. Static Segments
- Must match exactly
- Can contain alphanumeric characters, underscores, and hyphens
- Cannot contain consecutive dots

### 2. Single Wildcards (*)
- Match exactly one path segment
- Can appear anywhere in the path
- Multiple wildcards allowed

### 3. Multi-Level Wildcards (**)
- Match zero or more segments
- Cannot have consecutive multi-wildcards
- Most expensive match type

### Complexity Scoring

The router scores paths to ensure most specific matches take precedence:

1. Base score from segment count
2. Bonuses for exact matches (higher at start of path)
3. Penalties for wildcards (higher for ** than *)
4. Position weighting (earlier segments worth more)

## Managing Routes

Routes can be dynamically managed:

### Adding Routes
```elixir
{:ok, router} = Router.add(router, [
  {"metrics.**", %Instruction{
    action: MetricsHandler.Collect
  }},
  {"audit.*", %Instruction{
    action: AuditHandler.Log
  }, 75}
])
```

### Removing Routes
```elixir
# Remove a single route
{:ok, router} = Router.remove(router, "metrics.**")

# Remove multiple routes
{:ok, router} = Router.remove(router, [
  "audit.*",
  "user.created"
])
```

### Listing Routes
```elixir
{:ok, routes} = Router.list(router)

# Returns list of Route structs
[
  %Route{
    path: "user.created",
    instruction: %Instruction{...},
    priority: 0,
    match: nil
  }
]
```

## Integration with Agents

The Router integrates naturally with Agents:

```elixir
defmodule MyApp.UserAgent do
  use Jido.Agent,
    name: "user_agent",
    actions: [
      MyApp.Actions.HandleUserCreated,
      MyApp.Actions.HandleUserUpdated,
      MyApp.Actions.AuditUser
    ]
    
  def init(opts) do
    {:ok, router} = Router.new([
      {"user.created", %Instruction{
        action: MyApp.Actions.HandleUserCreated
      }},
      {"user.*.updated", %Instruction{
        action: MyApp.Actions.HandleUserUpdated
      }},
      {"user.**", %Instruction{
        action: MyApp.Actions.AuditUser
      }, 100}
    ])
    
    {:ok, Map.put(opts, :router, router)}
  end
  
  def handle_signal(%Signal{} = signal, state) do
    case Router.route(state.router, signal) do
      {:ok, instructions} -> 
        # Execute instructions in priority/complexity order
        Enum.reduce_while(instructions, {:ok, state}, fn instruction, {:ok, state} ->
          case run(instruction, state) do
            {:ok, new_state} -> {:cont, {:ok, new_state}}
            error -> {:halt, error}
          end
        end)
      
      {:error, _} = error -> error
    end
  end
end
```

## Best Practices

When working with the router, keep these principles in mind:

### 1. Path Design
- Use consistent, meaningful path segments
- Prefer exact matches over wildcards
- Put more specific routes first
- Document path patterns
- Consider future extensibility

### 2. Priority Management  
- Use priority ranges thoughtfully
- Reserve high/low ends for special cases
- Document priority meanings
- Consider complexity scoring
- Test priority interactions

### 3. Pattern Matching
- Keep match functions simple
- Handle nil/missing data gracefully
- Document matching conditions
- Test edge cases thoroughly
- Consider performance impact

### 4. Route Organization
- Group related functionality
- Use consistent naming
- Document path hierarchies
- Consider maintenance
- Plan for scale

### 5. Error Handling
- Validate routes early
- Handle missing routes gracefully
- Use Error structs consistently
- Log routing errors
- Provide clear context

## Testing

Here's how to thoroughly test your routing:

```elixir
defmodule MyApp.RouterTest do
  use ExUnit.Case
  
  alias Jido.Signal
  alias Jido.Instruction
  
  setup do
    routes = [
      {"user.created", %Instruction{
        action: MyApp.Actions.HandleUserCreated
      }},
      {"user.*.updated", %Instruction{
        action: MyApp.Actions.HandleUserUpdated
      }},
      {"user.**", %Instruction{
        action: MyApp.Actions.AuditUser
      }, 100}
    ]
    
    {:ok, router} = Router.new(routes)
    %{router: router}
  end
  
  test "routes signals correctly", %{router: router} do
    signal = %Signal{
      id: UUID.uuid4(),
      source: "/test",
      type: "user.123.updated",
      data: %{}
    }
    
    {:ok, instructions} = Router.route(router, signal)
    
    assert length(instructions) == 2  # audit and update handlers
    assert Enum.any?(instructions, & &1.action == MyApp.Actions.AuditUser)
    assert Enum.any?(instructions, & &1.action == MyApp.Actions.HandleUserUpdated)
  end
  
  test "respects priority and complexity", %{router: router} do
    signal = %Signal{
      id: UUID.uuid4(),
      source: "/test", 
      type: "user.created",
      data: %{}
    }
    
    {:ok, [first | _]} = Router.route(router, signal)
    assert first.action == MyApp.Actions.AuditUser
  end
  
  test "handles edge cases" do
    # Test empty segments
    assert {:error, _} = Router.new({"user..created", instruction})
    
    # Test consecutive wildcards
    assert {:error, _} = Router.new({"user.**.**.created", instruction})
    
    # Test priority bounds
    assert {:error, _} = Router.new({"test", instruction, 101})
    
    # Test pattern matching errors
    assert {:error, _} = Router.new({
      "test",
      fn _ -> raise "boom" end,
      instruction
    })
  end
end
```

## Next Steps

Now that you understand the Router, you can explore:
- Complex routing patterns
- Dynamic route management
- Custom pattern matching
- Performance optimization
- Integration with other Jido components

Remember: The Router is your signal traffic controller. Design your routes thoughtfully to ensure signals flow efficiently to their proper destinations.