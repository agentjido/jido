# Building Skills in JIDO

## Overview

Skills are the fundamental building blocks of agent capabilities in JIDO. A Skill encapsulates:

- Signal routing and handling patterns
- State management and isolation
- Process supervision
- Configuration management
- Runtime adaptation

Think of Skills as composable "feature packs" that give agents new abilities. Just as a human might learn new skills like "cooking" or "programming", JIDO agents gain new capabilities by incorporating Skills.

## Core Concepts

### 1. Skill Structure

A Skill is defined by several key components:

```elixir
defmodule MyApp.WeatherMonitorSkill do
  use Jido.Skill,
    name: "weather_monitor",
    description: "Monitors weather conditions and generates alerts",
    category: "monitoring",
    tags: ["weather", "alerts"],
    vsn: "1.0.0",
    schema_key: :weather,
    signals: [
      input: ["weather.data.received", "weather.alert.*"],
      output: ["weather.alert.generated"]
    ],
    config: [
      weather_api: [
        type: :map,
        required: true,
        doc: "Weather API configuration"
      ]
    ]
end
```

Let's break down each component:

- `name`: Unique identifier for the skill (required)
- `description`: Human-readable explanation of the skill's purpose
- `category`: Broad classification for organization
- `tags`: List of searchable tags
- `vsn`: Version string for compatibility checking
- `schema_key`: Atom key for state namespace isolation
- `signals`: Input/output signal patterns the skill handles
- `config`: Configuration schema for validation

### 2. State Management

Skills use `schema_key` for state namespace isolation. This prevents different skills from accidentally interfering with each other's state:

```elixir
def initial_state do
  %{
    current_conditions: nil,
    alert_history: [],
    last_update: nil
  }
end
```

This state will be stored under the skill's `schema_key` in the agent's state map:

```elixir
%{
  weather: %{  # Matches schema_key
    current_conditions: nil,
    alert_history: [],
    last_update: nil
  }
}
```

### 3. Signal Routing

Skills define signal routing patterns using a combination of exact matches, wildcards, and pattern matching functions:

```elixir
def router do
  [
    # High priority alerts
    %{
      path: "weather.alert.**",
      instruction: %{
        action: Actions.GenerateWeatherAlert
      },
      priority: 100
    },
    
    # Process incoming data
    %{
      path: "weather.data.received",
      instruction: %{
        action: Actions.ProcessWeatherData
      }
    },
    
    # Match severe conditions
    %{
      path: "weather.condition.*",
      match: fn signal ->
        get_in(signal.data, [:severity]) >= 3
      end,
      instruction: %{
        action: Actions.GenerateWeatherAlert
      },
      priority: 75
    }
  ]
end
```

### 4. Process Supervision

Skills can define child processes that need to run alongside the agent:

```elixir
def child_spec(config) do
  [
    {WeatherAPI.Sensor,
     [
       name: "weather_api",
       config: config.weather_api,
       interval: :timer.minutes(15)
     ]},
    {WeatherAlerts.Monitor,
     [
       name: "weather_alerts",
       config: config.alerts
     ]}
  ]
end
```

## Building Skills

### Step 1: Define the Skill Module

```elixir
defmodule MyApp.DataProcessingSkill do
  use Jido.Skill,
    name: "data_processor",
    description: "Processes and transforms data streams",
    schema_key: :processor,
    signals: [
      input: ["data.received.*", "data.transform.*"],
      output: ["data.processed.*"]
    ],
    config: [
      batch_size: [
        type: :pos_integer,
        default: 100,
        doc: "Number of items to process in each batch"
      ]
    ]
end
```

### Step 2: Implement Required Callbacks

```elixir
# Initial state for the skill's namespace
def initial_state do
  %{
    processed_count: 0,
    last_batch: nil,
    error_count: 0
  }
end

# Child processes to supervise
def child_spec(config) do
  [
    {DataProcessor.BatchWorker,
     [
       name: "batch_worker",
       batch_size: config.batch_size
     ]}
  ]
end

# Signal routing rules
def router do
  [
    %{
      path: "data.received.*",
      instruction: %{
        action: Actions.ProcessData
      }
    }
  ]
end
```

### Step 3: Define Actions

```elixir
defmodule MyApp.DataProcessingSkill.Actions do
  defmodule ProcessData do
    use Jido.Action,
      name: "process_data",
      description: "Processes incoming data batch",
      schema: [
        data: [type: {:list, :map}, required: true]
      ]

    def run(%{data: data}, context) do
      # Access skill config from context
      batch_size = get_in(context, [:config, :batch_size])
      
      # Process data...
      {:ok, %{
        processed: transformed_data,
        count: length(transformed_data)
      }}
    end
  end
end
```

## Testing Skills

### 1. Unit Testing Core Components

```elixir
defmodule MyApp.DataProcessingSkillTest do
  use ExUnit.Case
  alias MyApp.DataProcessingSkill
  
  describe "skill configuration" do
    test "validates config schema" do
      assert {:ok, config} = 
        Jido.Skill.validate_config(
          DataProcessingSkill,
          %{batch_size: 50}
        )
      
      assert config.batch_size == 50
    end
    
    test "rejects invalid config" do
      assert {:error, error} = 
        Jido.Skill.validate_config(
          DataProcessingSkill,
          %{batch_size: -1}
        )
      
      assert error.type == :validation_error
    end
  end
  
  describe "signal validation" do
    test "accepts valid signal patterns" do
      signal = %Jido.Signal{
        type: "data.received.batch",
        data: %{items: [1, 2, 3]}
      }
      
      assert :ok = 
        Jido.Skill.validate_signal(
          signal,
          DataProcessingSkill.signals()
        )
    end
  end
end
```

### 2. Integration Testing

```elixir
defmodule MyApp.DataProcessingSkill.IntegrationTest do
  use ExUnit.Case
  
  setup do
    # Start necessary processes
    start_supervised!(DataProcessor.BatchWorker)
    :ok
  end
  
  test "processes data through complete flow" do
    # Create test signal
    signal = %Jido.Signal{
      type: "data.received.batch",
      data: %{items: [1, 2, 3]}
    }
    
    # Find matching route
    [route] = Enum.filter(
      DataProcessingSkill.router(),
      &(&1.path == "data.received.*")
    )
    
    # Execute action
    {:ok, result} = route.instruction.action.run(
      %{data: signal.data.items},
      %{config: %{batch_size: 10}}
    )
    
    assert result.count == 3
    assert length(result.processed) == 3
  end
end
```

## Best Practices

1. **State Isolation**
   - Use meaningful `schema_key` names
   - Keep state focused and minimal
   - Document state structure
   - Consider persistence needs

2. **Signal Design**
   - Use consistent naming patterns
   - Document signal formats
   - Include necessary context
   - Consider routing efficiency

3. **Configuration**
   - Validate thoroughly
   - Provide good defaults
   - Document all options
   - Consider runtime changes

4. **Process Management**
   - Supervise child processes
   - Handle crashes gracefully
   - Monitor resource usage
   - Consider distribution

5. **Testing**
   - Test configuration validation
   - Test signal routing
   - Test state transitions
   - Test process lifecycle
   - Use property-based tests for complex logic

## Common Patterns

### 1. Stateful Processing

```elixir
defmodule StatefulSkill do
  use Jido.Skill,
    name: "stateful_processor",
    schema_key: :processor
    
  def router do
    [
      %{
        path: "data.received",
        instruction: %{
          action: Actions.Process
        }
      }
    ]
  end
  
  # State updates are handled by the action itself
  defmodule Actions.Process do
    use Jido.Action,
      name: "process_data"
      
    def run(params, context) do
      # Process data and return updates for state
      {:ok, %{
        last_result: processed_data,
        timestamp: DateTime.utc_now()
      }}
    end
  end
end
```

### 2. Conditional Routing

```elixir
def router do
  [
    %{
      path: "event.*",
      match: fn signal ->
        signal.data.priority == :high
      end,
      instruction: %{
        action: Actions.HandleHighPriority
      },
      priority: 100
    }
  ]
end
```

### 3. State Management

```elixir
defmodule StateManagementSkill do
  use Jido.Skill,
    name: "state_manager",
    schema_key: :manager

  def router do
    [
      %{
        path: "data.update",
        instruction: %{
          action: Actions.UpdateData
        }
      }
    ]
  end
  
  defmodule Actions.UpdateData do
    use Jido.Action,
      name: "update_data"
      
    def run(_params, context) do
      # Actions can read current state from context
      current_count = get_in(context, [:state, :manager, :count]) || 0
      
      # Return updates to be applied to state
      {:ok, %{
        count: current_count + 1,
        last_update: DateTime.utc_now()
      }}
    end
  end
end
```

## Troubleshooting

Common issues and solutions:

1. **Signal Not Routing**
   - Check signal type matches patterns
   - Verify skill is registered with agent
   - Check priority conflicts
   - Enable debug logging

2. **State Not Updating**
   - Verify transform function
   - Check schema_key path
   - Validate state structure
   - Check action results

3. **Process Crashes**
   - Review supervision strategy
   - Check resource limits
   - Monitor error counts
   - Add detailed logging

## Advanced Topics

### 1. Dynamic Configuration

Skills can adapt their behavior based on configuration:

```elixir
defmodule DynamicSkill do
  use Jido.Skill,
    name: "dynamic_processor",
    schema_key: :processor,
    config: [
      mode: [
        type: {:enum, [:fast, :thorough]},
        default: :fast,
        doc: "Processing mode to use"
      ]
    ]

  def router do
    [
      %{
        path: "data.*",
        match: fn signal -> 
          # Can use config to determine routing
          config = signal.metadata.config
          should_process?(signal.data, config.mode)
        end,
        instruction: %{
          action: Actions.ProcessData
        }
      }
    ]
  end
  
  defmodule Actions.ProcessData do
    use Jido.Action,
      name: "process_data"
      
    def run(params, context) do
      # Access config from context to determine behavior
      mode = get_in(context, [:config, :mode])
      
      result = case mode do
        :fast -> quick_process(params)
        :thorough -> detailed_process(params)
      end
      
      {:ok, result}
    end
  end
end
```

### 2. Composable Skills

Skills can be composed to build more complex capabilities:

```elixir
defmodule CompositeSkill do
  use Jido.Skill,
    name: "composite",
    signals: merge_signals([
      WeatherSkill.signals(),
      AlertSkill.signals()
    ])
    
  def child_spec(config) do
    WeatherSkill.child_spec(config) ++
    AlertSkill.child_spec(config)
  end
end
```

### 3. Distributed Skills

Skills can operate across nodes:

```elixir
def child_spec(config) do
  [
    {DistributedWorker,
     [
       name: {:global, "worker_1"},
       nodes: config.cluster_nodes
     ]}
  ]
end
```

## Conclusion

Skills are a powerful abstraction for building modular, composable agent capabilities. By following the patterns and practices in this guide, you can create robust, maintainable skills that enhance your agents' abilities while maintaining clean separation of concerns.

Remember:
- Keep skills focused and single-purpose
- Design clear signal interfaces
- Manage state carefully
- Test thoroughly
- Document extensively

For more examples and advanced patterns, refer to the test suite and example implementations in the JIDO codebase.