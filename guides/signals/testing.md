# Testing Signals

This guide covers comprehensive testing strategies for Jido's signal system components, including signal creation, dispatch, and routing. We'll explore test patterns, helper modules, and best practices for ensuring robust signal handling in your applications.

## Setting Up Signal Tests

### Test Helpers

Create test helpers to streamline signal testing:

```elixir
defmodule MyApp.SignalTestHelpers do
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

  def assert_signal_delivered(signal, config) do
    case Jido.Signal.Dispatch.dispatch(signal, config) do
      :ok -> true
      {:error, reason} -> flunk("Signal dispatch failed: #{inspect(reason)}")
    end
  end
end
```

### Test Case Setup

Set up your test cases with common signal testing requirements:

```elixir
defmodule MyApp.SignalTest do
  use ExUnit.Case
  import MyApp.SignalTestHelpers

  setup do
    # Start any required processes
    test_pid = self()

    # Create test signal and common configurations
    signal = build_test_signal()
    dispatch_config = {:pid, [target: test_pid, delivery_mode: :async]}

    {:ok, %{signal: signal, dispatch_config: dispatch_config}}
  end

  test "dispatches signal successfully", %{signal: signal, dispatch_config: config} do
    assert_signal_delivered(signal, config)
  end
end
```

## Testing Signal Creation

Test various signal creation scenarios:

```elixir
defmodule MyApp.SignalCreationTest do
  use ExUnit.Case

  test "creates basic signal" do
    attrs = %{
      type: "user.created",
      source: "/users",
      data: %{id: 123}
    }

    assert {:ok, signal} = Jido.Signal.new(attrs)
    assert signal.type == "user.created"
    assert signal.data.id == 123
  end

  test "validates required fields" do
    # Missing type
    attrs = %{source: "/test"}
    assert {:error, _} = Jido.Signal.new(attrs)
  end

  test "creates signal with instructions" do
    attrs = %{
      type: "task.process",
      source: "/tasks",
      data: %Instruction{action: ProcessTask, args: %{task_id: 456}},
    }

    assert {:ok, signal} = Jido.Signal.new(attrs)
    assert signal.data.action == ProcessTask
    assert signal.data.args.task_id == 456
  end
end
```

## Testing Signal Dispatch

### Testing Basic Dispatch

```elixir
defmodule MyApp.DispatchTest do
  use ExUnit.Case

  test "dispatches to pid synchronously" do
    signal = build_test_signal()
    test_pid = self()

    config = {:pid, [
      target: test_pid,
      delivery_mode: :sync,
      timeout: 1000
    ]}

    assert :ok = Jido.Signal.Dispatch.dispatch(signal, config)

    # Verify signal received
    assert_received {:signal, ^signal}
  end

  test "handles dispatch timeout" do
    signal = build_test_signal()
    slow_pid = spawn(fn ->
      receive do
        _ -> Process.sleep(2000)
      end
    end)

    config = {:pid, [
      target: slow_pid,
      delivery_mode: :sync,
      timeout: 100
    ]}

    assert {:error, :timeout} = Jido.Signal.Dispatch.dispatch(signal, config)
  end
end
```

### Testing Multiple Dispatch Targets

```elixir
defmodule MyApp.MultiDispatchTest do
  use ExUnit.Case

  test "dispatches to multiple targets" do
    signal = build_test_signal()
    test_pid = self()

    config = [
      {:pid, [target: test_pid]},
      {:logger, [level: :info]},
      {:console, []}
    ]

    assert :ok = Jido.Signal.Dispatch.dispatch(signal, config)
    assert_received {:signal, ^signal}
  end

  test "handles partial dispatch failure" do
    signal = build_test_signal()
    dead_pid = spawn(fn -> exit(:normal) end)
    Process.sleep(10) # Ensure process is dead

    config = [
      {:pid, [target: dead_pid]},
      {:logger, [level: :info]}
    ]

    assert {:error, :process_not_alive} = Jido.Signal.Dispatch.dispatch(signal, config)
  end
end
```

## Testing Signal Routing

### Testing Route Creation

```elixir
defmodule MyApp.RouterTest do
  use ExUnit.Case
  alias Jido.Signal.Router

  test "creates router with basic routes" do
    routes = [
      {"user.created", %Instruction{action: HandleUser}},
      {"payment.*", %Instruction{action: HandlePayment}},
      {"audit.**", %Instruction{action: AuditLog}}
    ]

    assert {:ok, router} = Router.new(routes)
    assert {:ok, all_routes} = Router.list(router)
    assert length(all_routes) == 3
  end

  test "validates route patterns" do
    # Invalid: consecutive dots
    routes = [{"user..created", %Instruction{action: HandleUser}}]
    assert {:error, _} = Router.new(routes)

    # Invalid: consecutive wildcards
    routes = [{"user.**.**", %Instruction{action: HandleUser}}]
    assert {:error, _} = Router.new(routes)
  end
end
```

### Testing Route Matching

```elixir
defmodule MyApp.RouteMatchingTest do
  use ExUnit.Case
  alias Jido.Signal.Router

  setup do
    routes = [
      {"user.created", %Instruction{action: HandleUser}},
      {"user.*.updated", %Instruction{action: HandleUserUpdate}},
      {"audit.**", %Instruction{action: AuditLog}, 100}
    ]

    {:ok, router} = Router.new(routes)
    {:ok, %{router: router}}
  end

  test "matches exact path", %{router: router} do
    signal = build_test_signal(type: "user.created")
    assert {:ok, [instruction]} = Router.route(router, signal)
    assert instruction.action == HandleUser
  end

  test "matches single wildcard", %{router: router} do
    signal = build_test_signal(type: "user.123.updated")
    assert {:ok, [instruction]} = Router.route(router, signal)
    assert instruction.action == HandleUserUpdate
  end

  test "matches multi-level wildcard", %{router: router} do
    signal = build_test_signal(type: "audit.user.created")
    assert {:ok, [instruction]} = Router.route(router, signal)
    assert instruction.action == AuditLog
  end

  test "respects priority ordering", %{router: router} do
    signal = build_test_signal(type: "audit.user.created")
    assert {:ok, [first | _]} = Router.route(router, signal)
    assert first.action == AuditLog
  end
end
```

### Testing Pattern Matching Routes

```elixir
defmodule MyApp.PatternMatchingTest do
  use ExUnit.Case
  alias Jido.Signal.Router

  test "matches based on signal content" do
    # Route with pattern matching function
    routes = [
      {"payment.processed",
        fn signal -> signal.data.amount > 1000 end,
        %Instruction{action: HandleLargePayment}
      }
    ]

    {:ok, router} = Router.new(routes)

    # Test large payment
    large_payment = build_test_signal(
      type: "payment.processed",
      data: %{amount: 2000}
    )
    assert {:ok, [instruction]} = Router.route(router, large_payment)
    assert instruction.action == HandleLargePayment

    # Test small payment
    small_payment = build_test_signal(
      type: "payment.processed",
      data: %{amount: 500}
    )
    assert {:error, _} = Router.route(router, small_payment)
  end
end
```

## Testing Common Patterns

### Testing Signal Transformation

```elixir
defmodule MyApp.SignalTransformationTest do
  use ExUnit.Case

  test "transforms signal data" do
    original = build_test_signal(
      type: "data.received",
      data: %{raw: "test"}
    )

    transformed = %{original |
      type: "data.processed",
      data: %{processed: String.upcase(original.data.raw)}
    }

    assert transformed.data.processed == "TEST"
  end
end
```

### Testing Signal Chains

```elixir
defmodule MyApp.SignalChainTest do
  use ExUnit.Case

  test "processes signal chain" do
    test_pid = self()

    chain = [
      {:pid, [target: test_pid, delivery_mode: :sync]},
      {:transform, fn signal ->
        %{signal | data: Map.put(signal.data, :processed, true)}
      end},
      {:pid, [target: test_pid, delivery_mode: :sync]}
    ]

    signal = build_test_signal()
    Enum.reduce(chain, signal, fn
      {:transform, func}, signal -> func.(signal)
      {adapter, opts}, signal ->
        assert :ok = Jido.Signal.Dispatch.dispatch(signal, {adapter, opts})
        signal
    end)
  end
end
```

## Best Practices

1. **Isolation**: Test signal components in isolation before testing interactions

```elixir
# Test signal creation separately
test "creates valid signal" do
  assert {:ok, signal} = build_valid_signal()
end

# Test dispatch separately
test "dispatch configuration is valid" do
  assert {:ok, _} = Dispatch.validate_opts(dispatch_config)
end

# Then test together
test "end-to-end signal flow" do
  assert {:ok, signal} = build_valid_signal()
  assert :ok = Dispatch.dispatch(signal, dispatch_config)
end
```

2. **Error Cases**: Test error handling extensively

```elixir
test "handles all error cases" do
  # Missing required fields
  assert {:error, _} = Jido.Signal.new(%{})

  # Invalid dispatch config
  assert {:error, _} = Dispatch.dispatch(signal, {:invalid, []})

  # Dead process
  assert {:error, :process_not_alive} = dispatch_to_dead_process()

  # Timeout
  assert {:error, :timeout} = dispatch_with_timeout()
end
```

3. **Mock Adapters**: Use the `:noop` adapter for testing

```elixir
test "uses noop adapter for testing" do
  config = {:noop, []}
  assert :ok = Dispatch.dispatch(signal, config)
end
```

4. **Async Testing**: Handle asynchronous dispatch correctly

```elixir
test "handles async dispatch" do
  test_pid = self()
  config = {:pid, [target: test_pid, delivery_mode: :async]}

  Dispatch.dispatch(signal, config)

  assert_receive {:signal, _}, 1000
end
```

## Common Pitfalls

1. **Race Conditions**: Be careful with async dispatch in tests

```elixir
# Wrong: May miss signal
test "wrong async test" do
  dispatch_async(signal)
  assert_received {:signal, _}  # Might fail
end

# Right: Use assert_receive with timeout
test "correct async test" do
  dispatch_async(signal)
  assert_receive {:signal, _}, 1000
end
```

2. **Resource Cleanup**: Always clean up test resources

```elixir
setup do
  # Start test process
  pid = start_test_process()

  on_exit(fn ->
    # Cleanup on test completion
    if Process.alive?(pid), do: Process.exit(pid, :normal)
  end)

  {:ok, %{test_pid: pid}}
end
```

3. **Context Isolation**: Ensure tests don't interfere

```elixir
test "isolates test context", %{test_pid: pid} do
  # Use unique identifiers for each test
  ref = make_ref()
  signal = build_test_signal(data: %{ref: ref})

  dispatch_to_pid(signal, pid)

  # Only match our specific signal
  assert_receive {:signal, %{data: %{ref: ^ref}}}
end
```

## See Also

- [Signal Overview](signals/overview.md) - Core signal concepts
- [Signal Dispatch](signals/dispatching.md) - Dispatch system details
- [Signal Router](signals/routing.md) - Routing system details
- `Jido.Signal.Router` - Router implementation
- `Jido.Signal.Dispatch` - Dispatch implementation
