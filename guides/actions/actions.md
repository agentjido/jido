# Actions & Workflows

This guide will introduce you to building composable, maintainable workflows using Jido's action-based architecture. Whether you're building autonomous agents, complex business processes, or distributed systems, Jido provides a robust foundation for your workflows.

## Understanding Core Concepts

Before diving into code, let's understand the foundational concepts of Jido and when to use them.

### Why Actions?

You might wonder: "Why should I wrap my code in Actions when I could just write regular Elixir functions?" This is a crucial question. If you're building a standard Elixir application without autonomous agents, you probably shouldn't use Actions – regular Elixir modules and functions would be simpler and more direct.

Actions exist specifically to support autonomous agent systems. When building agents that need to make independent decisions about what steps to take, you need a way to package functionality into discrete, composable units that the agent can reason about and combine in novel ways. Think of Actions as LEGO bricks for agents – standardized, well-described building blocks that can be assembled in different combinations to solve problems.

The Action system provides several critical features for agent-based systems:

- Comprehensive metadata for agent reasoning
- Schema validation using NimbleOptions
- Built-in telemetry and observability
- Enhanced error handling with compensation
- Improved runtime safety checks
- Dynamic composition through workflows
- IO operation safety monitoring
- Task group management for concurrent operations

### Core Components

Jido's action system consists of three main components:

1. **Actions**: Discrete, composable units of work that:

   - Have clear input/output contracts
   - Provide rich metadata
   - Support validation and compensation
   - Can be reasoned about by agents

2. **Workflows**: Sequences of Actions that:

   - Handle complex orchestration
   - Manage state transitions
   - Support conditional branching
   - Provide error recovery

3. **Agent Execution**: Runtime engine that:
   - Executes action sequences
   - Manages state flow
   - Handles errors and compensation
   - Provides telemetry and monitoring

## Creating Your First Action

Let's create a simple Action to understand the features:

```elixir
defmodule MyApp.Actions.FormatUser do
  use Jido.Action,
    name: "format_user",
    description: "Formats and validates user data",
    category: "user_management",
    tags: ["user", "formatting"],
    compensation: [
      enabled: true,
      max_retries: 3,
      timeout: 5000
    ],
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "User's full name - will be trimmed"
      ],
      email: [
        type: :string,
        required: true,
        doc: "Email address - will be normalized"
      ],
      age: [
        type: :integer,
        required: true,
        doc: "User's age in years"
      ]
    ]

  @impl true
  def run(params, context) do
    with {:ok, formatted} <- format_data(params) do
      Logger.warning("User data formatted #{inspect(formatted)}")

      {:ok, formatted}
    end
  end

  @impl true
  def on_error(failed_params, error, _context, _opts) do
    # Compensation logic for failures
    Logger.warning("Compensating for format failure",
      error: inspect(error),
      params: failed_params
    )

    {:ok, %{compensated: true, original_error: error}}
  end

  defp format_data(%{name: name, email: email, age: age}) do
    {:ok, %{
      formatted_name: String.trim(name),
      email: String.downcase(email),
      age: age,
      is_adult: age >= 18
    }}
  end
end
```

Let's break down the key features:

1. **Rich Metadata**:

   - `name`, `description`, `category`, and `tags` for better organization
   - Comprehensive schema documentation
   - Clear action description

2. **Compensation Support**:

   - Enable/disable compensation
   - Configure retries and timeouts
   - Custom compensation logic

3. **Structured Logging**:

   - Using `Logger.warning/2` for better observability
   - Context-aware logging
   - Error tracking

4. **Improved Error Handling**:
   - Clear error paths with `with` statements
   - Type-safe error returns
   - Compensation strategies

## Running Actions

Jido provides several ways to execute Actions, each with specific benefits:

### 1. Direct Execution

Best for testing and development - this does not provide any of the features of the workflow runtime.

```elixir
{:ok, result} = FormatUser.run(
  %{
    name: "John Doe ",
    email: "JOHN@EXAMPLE.COM",
    age: 30
  },
  %{request_id: "req_123"}
)
```

### 2. Workflow Runtime

For production use with full features:

```elixir
{:ok, result} = Jido.Workflow.run(
  FormatUser, # Action Module to run
  %{name: "John Doe", email: "john@example.com", age: 30}, # Input parameters
  %{request_id: "req_123"}, # Context
  timeout: 5000, # Runtime opts, such as timeout & retries
  max_retries: 2
)
```

The workflow runtime provides:

- Enhanced telemetry events
- IO operation safety checks
- Task group management
- Improved timeout handling
- Configurable retries
- Context propagation

### 3. Async Execution

For long-running operations:

```elixir
# Start async execution
async_ref = Jido.Workflow.run_async(
  FormatUser,
  params,
  context,
  timeout: 10_000
)

# Do other work...

# Get result with timeout
{:ok, result} = Jido.Workflow.await(async_ref, 5000)
```

## Building Complex Workflows

Let's create a complete user registration workflow:

```elixir
defmodule MyApp.Actions.EnrichUserData do
  use Jido.Action,
    name: "enrich_user_data",
    description: "Adds profile data to user record",
    category: "user_management",
    tags: ["user", "profile"],
    compensation: [enabled: true],
    schema: [
      formatted_name: [type: :string, required: true],
      email: [type: :string, required: true]
    ]

  def run(%{formatted_name: name, email: email}, context) do
    # Access task group from context if needed
    task_group = context[:__task_group__]

    with {:ok, username} <- generate_username(name, task_group),
         {:ok, avatar_url} <- get_avatar_url(email, task_group) do
      {:ok, %{
        username: username,
        avatar_url: avatar_url,
        profile_created_at: DateTime.utc_now()
      }}
    end
  end

  def on_error(params, error, _context, _opts) do
    Logger.warning("Compensating enrichment failure",
      error: inspect(error),
      params: params
    )
    {:ok, %{compensated: true}}
  end
end

defmodule MyApp.Actions.NotifyUser do
  use Jido.Action,
    name: "notify_user",
    description: "Sends welcome notification",
    category: "notifications",
    tags: ["user", "email"],
    compensation: [enabled: true],
    schema: [
      email: [type: :string, required: true],
      username: [type: :string, required: true]
    ]

  def run(params, context) do
    :telemetry.execute(
      [:myapp, :notification, :start],
      %{system_time: System.system_time()},
      %{email: params.email}
    )

    # Simulated notification
    Process.sleep(100)

    {:ok, %{
      notification_sent: true,
      notification_type: "welcome_email",
      sent_at: DateTime.utc_now()
    }}
  end
end
```

## Chaining Actions

Jido provides sophisticated chain functionality:

```elixir
alias Jido.Workflow.Chain

{:ok, result} = Chain.chain(
  [
    FormatUser,
    {EnrichUserData, max_retries: 3},
    {NotifyUser, timeout: 10_000}
  ],
  %{
    name: "John Doe",
    email: "john@example.com",
    age: 30
  },
  context: %{
    request_id: "req_123",
    tenant_id: "tenant_456"
  }
)
```

Key chain features:

- Per-action configuration
- Enhanced context propagation
- Better error handling
- Task group management
- IO safety monitoring

## Testing Strategies

Comprehensive testing strategies:

```elixir
defmodule MyApp.Actions.UserRegistrationTest do
  use ExUnit.Case, async: true
  import Mimic

  setup :verify_on_exit!

  @valid_user_data %{
    name: "John Doe ",
    email: "JOHN@EXAMPLE.COM",
    age: 30
  }

  describe "format user" do
    test "formats and validates user data" do
      {:ok, result} = FormatUser.run(@valid_user_data, %{})

      assert result.formatted_name == "John Doe"
      assert result.email == "john@example.com"
      assert result.is_adult == true
    end

    test "handles invalid data" do
      {:error, error} = FormatUser.run(%{}, %{})
      assert error.type == :validation_error
    end
  end

  describe "user registration workflow" do
    test "executes complete workflow" do
      expect(NotifyUser, :run, fn params, _context ->
        assert params.email == "john@example.com"
        {:ok, %{notification_sent: true}}
      end)

      {:ok, result} = Chain.chain(
        [FormatUser, EnrichUserData, NotifyUser],
        @valid_user_data
      )

      assert result.notification_sent == true
    end

    test "handles compensation on failure" do
      expect(EnrichUserData, :run, fn _params, _context ->
        {:error, "enrichment failed"}
      end)

      {:error, error} = Chain.chain(
        [FormatUser, EnrichUserData, NotifyUser],
        @valid_user_data
      )

      assert error.type == :execution_error
      assert error.details.compensated == true
    end
  end
end
```

Testing features:

- Enhanced Mimic integration
- Task group testing
- Compensation testing
- Telemetry testing
- IO safety verification

## Advanced Features

### 1. Task Groups

Task groups provide better concurrency management:

```elixir
defmodule MyApp.Actions.ParallelProcessor do
  use Jido.Action,
    name: "parallel_processor",
    schema: [items: [type: {:list, :map}, required: true]]

  def run(%{items: items}, %{__task_group__: group}) do
    results = Task.Supervisor.async_stream_nolink(
      group,
      items,
      &process_item/1,
      ordered: false
    )
    |> Enum.to_list()

    {:ok, %{results: results}}
  end
end
```

### 2. Telemetry Integration

Comprehensive telemetry support for monitoring:

```elixir
:telemetry.attach(
  "action-handler",
  [:jido, :workflow, :start],
  fn name, measurements, metadata, _config ->
    Logger.info("Action started",
      action: metadata.action,
      duration_us: measurements.system_time
    )
  end,
  nil
)
```

### 3. IO Safety

IO safety features prevent timeouts:

```elixir
defmodule MyApp.Actions.SafeProcessor do
  use Jido.Action,
    name: "safe_processor"

  def run(params, _context) do
    # This would trigger an IO safety warning:
    # IO.inspect(params)

    # Instead, use Logger:
    Logger.debug("Processing params", params: params)
    {:ok, process_data(params)}
  end
end
```

## Best Practices

1. **Action Design**:

   - Keep actions focused and single-purpose
   - Use comprehensive metadata
   - Enable compensation for critical operations
   - Leverage task groups for concurrency
   - Use structured logging

2. **Error Handling**:

   - Implement compensation strategies
   - Use with statements for clarity
   - Return structured errors
   - Log errors with context
   - Handle timeouts appropriately

3. **Testing**:

   - Test compensation paths
   - Verify telemetry events
   - Check IO safety
   - Test task group behavior
   - Use Mimic for mocking

4. **Performance**:

   - Monitor execution times
   - Use async operations appropriately
   - Configure timeouts properly
   - Manage task group resources
   - Implement backoff strategies

5. **Observability**:
   - Use structured logging
   - Attach telemetry handlers
   - Monitor compensation events
   - Track task group usage
   - Measure timing metrics

## Next Steps

Explore these advanced topics:

- Custom agent patterns for specialized workflows
- Distributed workflow execution
- Complex compensation strategies
- Advanced telemetry patterns
- Performance optimization

The test suite provides comprehensive examples of these patterns in action. For more details on specific features, consult the full API documentation.
