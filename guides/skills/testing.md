# Testing Skills in Jido

## Introduction

This guide covers comprehensive testing strategies for Jido Skills. Testing Skills requires a multi-faceted approach since they integrate multiple components:

- Signal routing and handling
- State management
- Process supervision
- Configuration validation
- Action execution

## Test Environment Setup

### Create Test Support Module

First, create a test support module with common helpers:

```elixir
defmodule MyApp.SkillTestSupport do
  use ExUnit.Case

  def build_test_signal(opts \\ []) do
    type = Keyword.get(opts, :type, "test.event")
    source = Keyword.get(opts, :source, "/test")
    data = Keyword.get(opts, :data, %{})

    {:ok, signal} = Jido.Signal.new(%{
      type: type,
      source: source,
      data: data
    })

    signal
  end

  def assert_skill_state(skill, state_path, expected) do
    actual = get_in(skill.state, state_path)
    assert actual == expected,
           "Expected state at #{inspect(state_path)} to be #{inspect(expected)}, got: #{inspect(actual)}"
  end
end
```

### Test Case Template

Create a test case template for skill tests:

```elixir
defmodule MyApp.SkillCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case
      import MyApp.SkillTestSupport
      alias Jido.Signal
      alias Jido.Skill

      # Setup common test state
      setup do
        skill_config = %{
          name: "test_skill",
          opts_key: :test
        }

        {:ok, %{config: skill_config}}
      end
    end
  end
end
```

## Unit Testing Skills

### Testing Configuration

Test skill configuration validation:

```elixir
defmodule MyApp.WeatherSkill.ConfigTest do
  use MyApp.SkillCase

  describe "configuration validation" do
    test "accepts valid config" do
      config = %{
        api_key: "test_key",
        update_interval: 5000
      }

      assert {:ok, validated} = WeatherSkill.validate_config(config)
      assert validated.api_key == "test_key"
    end

    test "rejects invalid config" do
      config = %{
        api_key: nil  # Required field
      }

      assert {:error, error} = WeatherSkill.validate_config(config)
      assert error.type == :validation_error
    end
  end
end
```

### Testing State Management

Test state initialization and updates:

```elixir
defmodule MyApp.WeatherSkill.StateTest do
  use MyApp.SkillCase

  describe "state management" do
    test "initializes with correct state" do
      initial_state = WeatherSkill.initial_state()

      assert %{
        current_conditions: nil,
        alert_history: [],
        last_update: nil
      } = initial_state
    end

    test "updates state correctly" do
      state = WeatherSkill.initial_state()

      # Simulate state update from signal
      signal = build_test_signal(
        type: "weather.data.received",
        data: %{temperature: 72}
      )

      {:ok, new_state} = WeatherSkill.handle_signal(signal, state)

      assert new_state.current_conditions.temperature == 72
      assert new_state.last_update != nil
    end
  end
end
```

### Testing Signal Routing

Test route matching and dispatch:

```elixir
defmodule MyApp.WeatherSkill.RoutingTest do
  use MyApp.SkillCase

  describe "signal routing" do
    test "matches exact paths" do
      routes = WeatherSkill.routes()
      signal = build_test_signal(type: "weather.data.received")

      assert {:ok, [instruction]} =
        Jido.Signal.Router.match(routes, signal)

      assert instruction.action == WeatherSkill.Actions.ProcessData
    end

    test "matches wildcard patterns" do
      routes = WeatherSkill.routes()
      signal = build_test_signal(type: "weather.alert.severe")

      assert {:ok, [instruction]} =
        Jido.Signal.Router.match(routes, signal)

      assert instruction.action == WeatherSkill.Actions.HandleAlert
    end

    test "respects priority ordering" do
      routes = WeatherSkill.routes()
      signal = build_test_signal(type: "weather.alert.emergency")

      assert {:ok, [first | _]} =
        Jido.Signal.Router.match(routes, signal)

      # High priority handlers should match first
      assert first.priority == 100
    end
  end
end
```

## Integration Testing

### Testing with Agent Integration

Test skill behavior within an agent:

```elixir
defmodule MyApp.WeatherSkill.IntegrationTest do
  use MyApp.SkillCase

  setup do
    # Start agent with skill
    {:ok, agent} = TestAgent.start_link(
      name: "test_agent",
      skills: [WeatherSkill]
    )

    {:ok, %{agent: agent}}
  end

  test "processes signals through agent", %{agent: agent} do
    # Send test signal
    signal = build_test_signal(
      type: "weather.data.received",
      data: %{temperature: 72}
    )

    :ok = TestAgent.process_signal(agent, signal)

    # Verify skill state was updated
    assert_skill_state(agent, [:weather, :current_conditions],
      %{temperature: 72})
  end

  test "handles multiple skills", %{agent: agent} do
    # Add another skill
    :ok = TestAgent.add_skill(agent, MetricsSkill)

    # Both skills should process appropriate signals
    weather_signal = build_test_signal(
      type: "weather.data.received"
    )
    metrics_signal = build_test_signal(
      type: "metrics.collected"
    )

    :ok = TestAgent.process_signal(agent, weather_signal)
    :ok = TestAgent.process_signal(agent, metrics_signal)

    # Verify both skills processed their signals
    assert_skill_state(agent, [:weather], %{processed: true})
    assert_skill_state(agent, [:metrics], %{processed: true})
  end
end
```

### Testing Process Supervision

Test child process management:

```elixir
defmodule MyApp.WeatherSkill.SupervisionTest do
  use MyApp.SkillCase

  test "supervises child processes" do
    # Start skill with child processes
    {:ok, skill} = WeatherSkill.start_link()

    # Get child process
    [{_, worker_pid, _, _}] =
      Supervisor.which_children(skill.supervisor)

    # Kill worker
    Process.exit(worker_pid, :kill)

    # Worker should restart
    :timer.sleep(100)
    [{_, new_pid, _, _}] =
      Supervisor.which_children(skill.supervisor)

    assert new_pid != worker_pid
    assert Process.alive?(new_pid)
  end
end
```

## Property-Based Testing

Use property testing for complex validation:

```elixir
defmodule MyApp.WeatherSkill.PropertyTest do
  use ExUnit.Case
  use PropCheck

  property "validates all signal types" do
    forall signal_type <- signal_type() do
      signal = build_test_signal(type: signal_type)
      {:ok, _} = WeatherSkill.validate_signal(signal)
    end
  end

  # Generators
  def signal_type do
    let [
      domain <- elements(["weather", "alert"]),
      action <- elements(["received", "processed", "error"]),
      id <- integer(1, 1000)
    ] do
      "#{domain}.#{action}.#{id}"
    end
  end
end
```

## Best Practices

### 1. Test Organization

- Group tests by functionality (config, state, routing)
- Use descriptive test names
- Follow arrange-act-assert pattern
- Keep tests focused and isolated

### 2. Test Coverage

- Test all configuration options
- Verify signal routing patterns
- Check state transitions
- Test error handling
- Verify process supervision

### 3. Test Data

- Use factories for complex test data
- Randomize data when appropriate
- Test edge cases explicitly
- Use property testing for validation

### 4. Async Testing

- Be careful with async tests
- Use proper process cleanup
- Handle timing dependencies
- Test concurrent operations

## Common Testing Patterns

### 1. State Verification

```elixir
test "verifies state updates" do
  {:ok, skill} = TestSkill.start_link()

  # Initial state
  assert_skill_state(skill, [:count], 0)

  # Update state
  signal = build_test_signal(type: "increment")
  :ok = TestSkill.process_signal(skill, signal)

  # Verify update
  assert_skill_state(skill, [:count], 1)
end
```

### 2. Signal Flow Testing

```elixir
test "tracks signal flow" do
  {:ok, skill} = TestSkill.start_link()

  # Track signal processing
  ref = Process.monitor(skill.pid)
  signal = build_test_signal()

  # Send signal
  :ok = TestSkill.process_signal(skill, signal)

  # Verify processing
  assert_receive {:signal_processed, ^signal}, 1000
end
```

### 3. Error Handling

```elixir
test "handles errors gracefully" do
  {:ok, skill} = TestSkill.start_link()

  # Invalid signal
  signal = build_test_signal(type: "invalid")

  # Should not crash
  :ok = TestSkill.process_signal(skill, signal)
  assert Process.alive?(skill.pid)

  # Should log error
  assert_receive {:error, "Invalid signal type"}
end
```

## See Also

- [Signal Testing](../signals/testing.md)
- [Agent Testing](../signals/testing.md)
- [Action Testing](../actions/testing.md)
- [Child Processes](../agents/child-processes.md)
