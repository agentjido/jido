# Action Configuration

This guide covers how to configure Jido actions for optimal performance and behavior in your application.

## Timeout Configuration

Timeout configuration is one of the most important aspects of action setup, as it determines how long actions can run before being terminated.

### Global Configuration

Set the default timeout for all actions in your application configuration:

```elixir
# config/config.exs
config :jido, default_timeout: 60_000  # 60 seconds (default: 30 seconds)

# For production environments, you might want longer timeouts
# config/prod.exs  
config :jido, default_timeout: 120_000  # 2 minutes
```

### Runtime Configuration Levels

Jido supports timeout configuration at multiple levels with clear precedence rules:

#### 1. Direct Execution Timeouts (Highest Precedence)

```elixir
# Override timeout for specific execution
{:ok, result} = Jido.Exec.run(MyAction, params, context, timeout: 45_000)

# Disable timeout completely
{:ok, result} = Jido.Exec.run(MyAction, params, context, timeout: 0)
```

#### 2. Instruction-Level Timeouts

```elixir
# Set timeout in instruction options
instruction = %Jido.Instruction{
  action: LongRunningAction,
  params: %{data: large_dataset},
  opts: [timeout: 300_000]  # 5 minutes for this specific action
}
```

#### 3. Runner-Level Timeouts

```elixir
# Apply timeout to all instructions processed by runner
{:ok, agent, directives} = Jido.Runner.Simple.run(agent, timeout: 45_000)
{:ok, agent, directives} = Jido.Runner.Chain.run(agent, timeout: 120_000)
```

#### 4. Global Configuration (Lowest Precedence)

The global configuration serves as the default when no other timeout is specified.

### Timeout Precedence Example

```elixir
# Global config: 30 seconds
config :jido, default_timeout: 30_000

# Runner timeout: 60 seconds (overrides global for instructions without timeout)
runner_opts = [timeout: 60_000]

instructions = [
  %Instruction{
    action: FastAction,
    opts: [timeout: 5_000]    # Uses 5 seconds (instruction-level wins)
  },
  %Instruction{
    action: NormalAction,
    opts: []                  # Uses 60 seconds (runner-level)
  }
]

# Direct execution override: 10 seconds (highest precedence)
{:ok, result} = Jido.Exec.run(UrgentAction, params, context, timeout: 10_000)
```

## Special Timeout Values

### Infinite Timeout

Use `timeout: 0` to disable timeout completely:

```elixir
# For long-running batch operations
{:ok, result} = Jido.Exec.run(BatchProcessor, 
  %{items: millions_of_items}, 
  %{}, 
  timeout: 0
)

# In instruction options
batch_instruction = %Instruction{
  action: DataMigration,
  params: %{migration_id: "2024_01_big_migration"},
  opts: [timeout: 0]  # No time limit
}
```

**⚠️ Warning**: Use infinite timeouts sparingly. They can lead to resource exhaustion and make your system unresponsive.

### Recommended Timeout Values

| Use Case | Recommended Timeout | Example |
|----------|-------------------|---------|
| Quick calculations | 5-15 seconds | Math operations, simple validations |
| API calls | 30-60 seconds | External service calls, HTTP requests |
| Database operations | 30-120 seconds | Complex queries, bulk inserts |
| File processing | 2-10 minutes | Image processing, PDF generation |
| Data migrations | No timeout | Large dataset operations |

## Agent Integration

Agents can configure default timeouts for their runners:

### Simple Agent Configuration

```elixir
defmodule MyApp.ProcessingAgent do
  use Jido.Agent,
    name: "processing_agent",
    runner: Jido.Runner.Simple

  def start_link(opts \\ []) do
    # Set default timeout for this agent's runner
    runner_opts = [timeout: 90_000]  # 90 seconds
    opts = Keyword.put(opts, :runner_opts, runner_opts)
    super(opts)
  end
end
```

### Chain Agent Configuration

```elixir
defmodule MyApp.WorkflowAgent do
  use Jido.Agent,
    name: "workflow_agent", 
    runner: Jido.Runner.Chain

  def start_link(opts \\ []) do
    # Longer timeout for complex workflows
    runner_opts = [
      timeout: 300_000,        # 5 minutes per action
      merge_results: true,     # Chain results between actions
      apply_directives?: true  # Apply directives during execution
    ]
    opts = Keyword.put(opts, :runner_opts, runner_opts)
    super(opts)
  end
end
```

## Environment-Specific Configuration

Different environments often require different timeout configurations:

```elixir
# config/config.exs - Base configuration
config :jido, default_timeout: 30_000

# config/dev.exs - Development (faster feedback)
config :jido, default_timeout: 15_000

# config/test.exs - Testing (quick failures)
config :jido, default_timeout: 5_000

# config/prod.exs - Production (more tolerance)
config :jido, default_timeout: 120_000
```

## Runtime Configuration Updates

For dynamic timeout adjustments based on system load or other factors:

```elixir
defmodule MyApp.AdaptiveTimeout do
  def get_timeout_for_action(action) do
    base_timeout = Application.get_env(:jido, :default_timeout, 30_000)
    
    case action do
      # CPU-intensive actions need more time
      action when action in [ImageProcessor, DataAnalyzer] ->
        base_timeout * 3
        
      # Quick actions can use less time  
      action when action in [Validator, Formatter] ->
        div(base_timeout, 2)
        
      # Default timeout for unknown actions
      _ ->
        base_timeout
    end
  end
end

# Usage
timeout = MyApp.AdaptiveTimeout.get_timeout_for_action(MyAction)
{:ok, result} = Jido.Exec.run(MyAction, params, context, timeout: timeout)
```

## Monitoring and Debugging

### Timeout Logging

Enable timeout-specific logging to monitor action performance:

```elixir
# Enable debug logging for timeouts
{:ok, result} = Jido.Exec.run(MyAction, params, context, 
  timeout: 60_000, 
  log_level: :debug
)
```

### Timeout Telemetry

Monitor timeout patterns using Jido's built-in telemetry:

```elixir
:telemetry.attach(
  "timeout-monitor",
  [:jido, :action, :error],
  fn name, measurements, metadata, config ->
    case metadata.result do
      {:error, %{type: :timeout}} ->
        Logger.warning("Action timeout: #{metadata.action}", metadata)
      _ -> :ok
    end
  end,
  nil
)
```

## Best Practices

1. **Set appropriate defaults**: Configure global timeouts based on your application's typical action duration
2. **Use environment-specific configs**: Different environments need different timeout tolerances
3. **Monitor timeout patterns**: Track which actions frequently timeout and adjust accordingly
4. **Prefer specific over general**: Use instruction-level timeouts for actions with known special requirements
5. **Test timeout scenarios**: Include timeout testing in your test suite
6. **Document timeout decisions**: Explain why specific timeouts were chosen for critical actions

## Troubleshooting

### Common Timeout Issues

**Actions timing out frequently**
- Increase timeout for that specific action or globally
- Optimize the action's implementation
- Check for blocking operations or inefficient algorithms

**Actions running too long**
- Decrease timeout to fail faster
- Add progress indicators or chunking for long operations
- Consider breaking large actions into smaller ones

**Inconsistent timeout behavior**
- Check timeout precedence rules
- Verify configuration is loaded correctly
- Look for runtime timeout overrides

### Debugging Timeout Configuration

```elixir
# Check current timeout configuration
current_default = Application.get_env(:jido, :default_timeout)
IO.puts("Global default timeout: #{current_default}ms")

# Test timeout precedence
instruction = %Instruction{action: TestAction, opts: [timeout: 5000]}
IO.puts("Instruction timeout: #{instruction.opts[:timeout]}ms")
```

## Next Steps

- Learn about [Action Testing](testing.md) including timeout scenarios
- Explore [Runner Configuration](runners.md) for advanced timeout handling
- Check out [Workflow Execution](workflows.md) for timeout in complex workflows
