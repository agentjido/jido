# Skills Overview

## Introduction

Skills are a module to group a set of Routing rules, Sensors and Actions into a Plugin of functionality for a Jido Agent. As your agents grow and get more sophisticated, the intent is to support just adding a "Chat Skill" or "Database Skill" to an Agent that accepts a few customization parameters - empowering your agent with a useful set of functionality very easily.

A Skill encapsulates:

- Signal routing and handling patterns
- State management and isolation
- Process supervision
- Configuration management
- Runtime adaptation

## Core Concepts

### 1. Skill Structure

A Skill is defined by creating a module that uses the `use Jido.Skill` macro.

```elixir
defmodule MyApp.WeatherMonitorSkill do
  use Jido.Skill,
    name: "weather_monitor",
    description: "Monitors weather conditions and generates alerts",
    category: "monitoring",
    tags: ["weather", "alerts"],
    vsn: "1.0.0",
    # An optional schema key to namespace the skill's state
    opts_key: :weather,
    # An optional list of signals the skill will handle
    signals: [
      input: ["weather.data.received", "weather.alert.*"],
      output: ["weather.alert.generated"]
    ],
    # An optional configuration schema for the skill
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
- `opts_key`: Atom key for state namespace isolation
- `signals`: Input/output signal patterns the skill handles
- `config`: Configuration schema for validation

### 2. State Management

Skills use `opts_key` for state namespace isolation. This prevents different skills from accidentally interfering with each other's state:

```elixir
def initial_state do
  %{
    current_conditions: nil,
    alert_history: [],
    last_update: nil
  }
end
```

This state will be stored under the skill's `opts_key` in the agent's state map:

```elixir
%{
  weather: %{  # Matches opts_key
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

## Building Skills

### Step 1: Define the Skill Module

```elixir
defmodule MyApp.DataProcessingSkill do
  use Jido.Skill,
    name: "data_processor",
    description: "Processes and transforms data streams",
    opts_key: :processor,
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

# Child processes to supervise, such as custom Sensors
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

## Best Practices

1. **State Isolation**

   - Use meaningful `opts_key` names
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

## Sharing and Distribution

Skills are designed to be shared and reused across different Jido applications. They act as plugins that can extend agent capabilities:

1. **Package as Library**

   - Create dedicated package
   - Document dependencies
   - Version appropriately
   - Include examples

2. **Distribution**
   - Publish to Hex.pm
   - Document installation
   - Provide configuration guide
   - Include integration examples

## Example Shared Skills

Some common types of shared skills:

1. **Integration Skills**

   - Database connectors
   - API clients
   - Message queue adapters
   - File system monitors

2. **Processing Skills**

   - Data transformation
   - Content analysis
   - Format conversion
   - Batch processing

3. **Monitoring Skills**
   - System metrics
   - Performance tracking
   - Error detection
   - Health checks

## See Also

- [Testing Skills](testing.md)
- [Signal Router](../signals/routing.md)
- [Agent State](../agents/stateful.md)
- [Child Processes](../agents/child-processes.md)
