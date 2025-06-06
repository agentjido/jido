# Jido Usage Rules

**Jido** is a functional, OTP-based toolkit for building autonomous, distributed agent systems in Elixir. These usage rules help ensure proper implementation patterns when working with Jido's core concepts: Actions, Agents, Sensors, Signals, and Skills.

## Core Philosophy

Jido follows **functional programming principles** with **OTP integration**:
- Pure functions where possible
- Immutable state management with validation
- Pattern matching for control flow
- Tagged tuple returns (`{:ok, result}` or `{:error, reason}`)
- Supervision trees for fault tolerance
- Composable, reusable building blocks

## Essential Patterns

### 1. Actions - Building Blocks

Actions are discrete, composable units of functionality. **Always** structure them as pure functions with validation:

```elixir
defmodule MyApp.Actions.ProcessData do
  use Jido.Action,
    name: "process_data",
    description: "Processes input data with validation",
    schema: [
      input: [type: :string, required: true],
      options: [type: :map, default: %{}]
    ]

  @impl true
  def run(params, _context) do
    # Use pattern matching and with statements
    with {:ok, cleaned} <- clean_input(params.input),
         {:ok, processed} <- process_cleaned(cleaned, params.options) do
      {:ok, %{result: processed, metadata: %{processed_at: DateTime.utc_now()}}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions should be pure
  defp clean_input(input) when is_binary(input) do
    {:ok, String.trim(input)}
  end
  defp clean_input(_), do: {:error, :invalid_input}
end
```

**DO:**
- Use schemas for parameter validation
- Return tagged tuples consistently 
- Keep `run/2` functions focused and pure
- Use pattern matching for control flow
- Include meaningful error messages

**DON'T:**
- Put side effects in run functions without proper error handling
- Skip parameter validation
- Return raw values instead of tagged tuples
- Make Actions stateful

### 2. Agents - Stateful Orchestrators

Agents manage state and coordinate Action execution. They are **OTP GenServers** with validation:

```elixir
defmodule MyApp.WorkflowAgent do
  use Jido.Agent,
    name: "workflow_agent",
    description: "Manages complex workflow execution",
    schema: [
      status: [type: :atom, values: [:idle, :running, :completed, :failed], default: :idle],
      step_count: [type: :integer, default: 0],
      results: [type: :list, default: []]
    ],
    actions: [
      MyApp.Actions.ProcessData,
      MyApp.Actions.ValidateResult,
      MyApp.Actions.SaveOutput
    ]

  # Lifecycle hooks for validation
  @impl true
  def on_before_validate_state(state) do
    if valid_transition?(state) do
      {:ok, state}
    else
      {:error, :invalid_state_transition}
    end
  end

  # Use pattern matching in private functions
  defp valid_transition?(%{status: :idle}), do: true
  defp valid_transition?(%{status: :running, step_count: count}) when count >= 0, do: true
  defp valid_transition?(_), do: false
end
```

**Agent Execution Patterns:**

```elixir
# Synchronous execution (blocking)
{:ok, agent} = MyApp.WorkflowAgent.start_link(id: "workflow-1")
{:ok, result} = MyApp.WorkflowAgent.cmd(agent, ProcessData, %{input: "data"})

# Asynchronous execution (non-blocking)
{:ok, ref} = MyApp.WorkflowAgent.cmd_async(agent, ProcessData, %{input: "data"})

# Chain multiple actions
instructions = [
  {ProcessData, %{input: "raw_data"}},
  {ValidateResult, %{threshold: 0.8}},
  SaveOutput
]
{:ok, agent} = MyApp.WorkflowAgent.plan(agent, instructions)
{:ok, final_result} = MyApp.WorkflowAgent.run(agent)
```

**DO:**
- Define clear state schemas with validation
- Use lifecycle hooks for state transition validation
- Plan instruction sequences before execution
- Handle errors gracefully with compensation
- Use supervision trees in production

**DON'T:**
- Mutate state directly outside of the Agent server
- Skip state validation
- Create circular dependencies between agents
- Use agents for stateless operations (use Actions instead)

### 3. Sensors - Event Monitoring

Sensors provide real-time monitoring and data collection:

```elixir
defmodule MyApp.Sensors.MetricsCollector do
  use Jido.Sensor,
    name: "metrics_collector",
    description: "Collects system performance metrics",
    schema: [
      collection_interval: [type: :pos_integer, default: 5000],
      metrics_types: [type: {:list, :atom}, default: [:cpu, :memory]]
    ]

  @impl true
  def mount(opts) do
    state = %{
      timer_ref: nil,
      collected_metrics: [],
      interval: opts.collection_interval
    }
    {:ok, schedule_collection(state)}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    metrics = collect_system_metrics(state.metrics_types)
    new_state = %{state | collected_metrics: [metrics | state.collected_metrics]}
    
    # Process collected data
    Logger.info("Metrics collected: #{inspect(metrics)}")
    
    {:noreply, schedule_collection(new_state)}
  end

  defp schedule_collection(state) do
    timer_ref = Process.send_after(self(), :collect_metrics, state.interval)
    %{state | timer_ref: timer_ref}
  end
end
```



## OTP Integration Patterns

### Supervision Trees

Always structure agents within supervision trees:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [

      
      # Agent supervisor for dynamic agents
      {DynamicSupervisor, name: MyApp.AgentSupervisor, strategy: :one_for_one},
      
      # Static agents
      {MyApp.WorkflowAgent, id: "main_workflow"},
      {MyApp.MonitoringAgent, id: "system_monitor"},
      
      # Sensors
      {MyApp.Sensors.MetricsCollector, []}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Dynamic Agent Management

```elixir
# Starting agents dynamically
spec = {MyApp.WorkflowAgent, id: "dynamic_workflow_#{System.unique_integer()}"}
{:ok, pid} = DynamicSupervisor.start_child(MyApp.AgentSupervisor, spec)

# Clean shutdown
:ok = DynamicSupervisor.terminate_child(MyApp.AgentSupervisor, pid)
```

## Error Handling Patterns

### Action Error Handling

```elixir
defmodule MyApp.Actions.ResilientOperation do
  use Jido.Action,
    name: "resilient_operation",
    description: "Operation with retry logic"

  @impl true
  def run(params, context) do
    case attempt_operation(params) do
      {:ok, result} -> 
        {:ok, result}
      {:error, :temporary_failure} -> 
        retry_with_backoff(params, context)
      {:error, :permanent_failure} = error -> 
        error
    end
  end

  defp retry_with_backoff(params, context, attempt \\ 1) do
    if attempt <= 3 do
      :timer.sleep(attempt * 1000)
      case attempt_operation(params) do
        {:ok, result} -> {:ok, result}
        {:error, :temporary_failure} -> retry_with_backoff(params, context, attempt + 1)
        {:error, _} = error -> error
      end
    else
      {:error, :max_retries_exceeded}
    end
  end
end
```

### Agent Error Recovery

```elixir
defmodule MyApp.FaultTolerantAgent do
  use Jido.Agent,
    name: "fault_tolerant_agent"

  @impl true
  def on_error(agent, error) do
    case error do
      %{type: :temporary_error} ->
        # Log and continue
        Logger.warning("Temporary error occurred", error: error)
        {:ok, agent}
      
      %{type: :validation_error} ->
        # Reset to known good state
        safe_state = get_safe_state(agent)
        {:ok, %{agent | state: safe_state}}
      
      _ ->
        # Re-raise for supervisor handling
        {:error, error}
    end
  end
end
```

## Testing Patterns

### Action Testing

```elixir
defmodule MyApp.Actions.ProcessDataTest do
  use ExUnit.Case, async: true
  
  alias MyApp.Actions.ProcessData

  describe "run/2" do
    test "processes valid input successfully" do
      params = %{input: "  test data  ", options: %{trim: true}}
      
      assert {:ok, result} = ProcessData.run(params, %{})
      assert result.result == "test data"
      assert %DateTime{} = result.metadata.processed_at
    end

    test "handles invalid input gracefully" do
      params = %{input: nil, options: %{}}
      
      assert {:error, :invalid_input} = ProcessData.run(params, %{})
    end

    test "validates required parameters" do
      params = %{options: %{}}  # missing required :input
      
      assert {:error, _validation_error} = ProcessData.run(params, %{})
    end
  end
end
```

### Agent Testing

```elixir
defmodule MyApp.WorkflowAgentTest do
  use ExUnit.Case, async: true
  
  alias MyApp.WorkflowAgent

  setup do
    {:ok, agent} = WorkflowAgent.start_link(id: "test_agent")
    %{agent: agent}
  end

  test "executes single action", %{agent: agent} do
    params = %{input: "test"}
    
    assert {:ok, result} = WorkflowAgent.cmd(agent, ProcessData, params)
    assert result.success == true
  end

  test "handles state transitions", %{agent: agent} do
    # Test valid transition
    assert {:ok, _} = WorkflowAgent.set_state(agent, %{status: :running})
    
    # Test invalid transition
    assert {:error, :invalid_state_transition} = 
      WorkflowAgent.set_state(agent, %{status: :invalid})
  end
end
```

## Common Anti-Patterns to Avoid

### ❌ Don't Use OOP Patterns
```elixir
# BAD: Object-oriented style
defmodule BadAgent do
  def new(), do: %__MODULE__{data: nil}
  def set_data(%__MODULE__{} = agent, data), do: %{agent | data: data}
  def get_data(%__MODULE__{data: data}), do: data
end

# GOOD: Use Jido.Agent with proper OTP integration
defmodule GoodAgent do
  use Jido.Agent, schema: [data: [type: :any]]
end
```

### ❌ Don't Skip Validation
```elixir
# BAD: No parameter validation
def run(params, _context) do
  result = String.upcase(params.name)  # Could crash on nil
  {:ok, result}
end

# GOOD: Schema validation
use Jido.Action, schema: [name: [type: :string, required: true]]
```

### ❌ Don't Create Tightly Coupled Components
```elixir
# BAD: Direct module dependencies
defmodule TightlyCoupledAction do
  def run(params, _context) do
    # Directly calling another module
    result = AnotherSpecificModule.process(params)
    {:ok, result}
  end
end

# GOOD: Use instruction composition
defmodule LooselyComposed do
  def create_workflow(params) do
    [
      {ProcessInput, params},
      {ValidateOutput, %{rules: params.validation_rules}},
      TransformResult
    ]
  end
end
```

### ❌ Don't Ignore Error Propagation
```elixir
# BAD: Swallowing errors
def run(params, _context) do
  try do
    risky_operation(params)
    {:ok, "success"}
  rescue
    _ -> {:ok, "failed"}  # Don't do this!
  end
end

# GOOD: Proper error handling
def run(params, _context) do
  case risky_operation(params) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, reason}
  end
end
```

## Configuration Patterns

### Environment-Based Configuration

```elixir
# config/config.exs
config :my_app, MyApp.WorkflowAgent,
  max_retries: 3,
  timeout: 30_000,
  batch_size: 100

# config/prod.exs
config :my_app, MyApp.WorkflowAgent,
  max_retries: 5,
  timeout: 60_000,
  batch_size: 500
```

### Agent Configuration

```elixir
defmodule MyApp.ConfigurableAgent do
  use Jido.Agent,
    name: "configurable_agent"

  def start_link(opts) do
    config = Application.get_env(:my_app, __MODULE__, [])
    merged_opts = Keyword.merge(config, opts)
    
    Jido.Agent.start_link(__MODULE__, merged_opts)
  end
end
```

## Performance Considerations

### Batch Processing
```elixir
defmodule MyApp.Actions.BatchProcessor do
  use Jido.Action,
    schema: [
      items: [type: {:list, :any}, required: true],
      batch_size: [type: :pos_integer, default: 100]
    ]

  def run(%{items: items, batch_size: batch_size}, _context) do
    results = 
      items
      |> Enum.chunk_every(batch_size)
      |> Enum.map(&process_batch/1)
      |> List.flatten()
    
    {:ok, %{results: results, total_processed: length(results)}}
  end
end
```

### Async Operations
```elixir
# For CPU-bound tasks, use Task.async/await
def run(params, _context) do
  tasks = 
    params.data_chunks
    |> Enum.map(fn chunk -> 
      Task.async(fn -> process_chunk(chunk) end)
    end)
  
  results = Task.await_many(tasks, 30_000)
  {:ok, %{results: results}}
end
```

## Integration with External Services

### HTTP Clients
```elixir
defmodule MyApp.Actions.FetchData do
  use Jido.Action,
    schema: [url: [type: :string, required: true]]

  def run(%{url: url}, _context) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{data: body}}
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end
end
```

### Database Operations
```elixir
defmodule MyApp.Actions.SaveRecord do
  use Jido.Action,
    schema: [
      table: [type: :string, required: true],
      data: [type: :map, required: true]
    ]

  def run(%{table: table, data: data}, context) do
    repo = context[:repo] || MyApp.Repo
    
    case repo.insert_all(table, [data]) do
      {1, _} -> {:ok, %{inserted: true}}
      {0, _} -> {:error, :insert_failed}
    end
  end
end
```

## Summary

Jido emphasizes **functional programming with OTP reliability**. Always:

1. **Use schemas** for validation
2. **Return tagged tuples** consistently
3. **Leverage pattern matching** for control flow
4. **Compose Actions** instead of creating monoliths
5. **Handle errors** explicitly
6. **Test thoroughly** with unit and integration tests
7. **Follow OTP supervision** patterns
8. **Keep components loosely coupled**

When in doubt, favor **pure functions**, **explicit error handling**, and **composable design** over complex, stateful operations. 