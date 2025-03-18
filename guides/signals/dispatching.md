# Signal Dispatching

## Overview

Signal dispatching is a core mechanism in Jido that enables flexible, configurable message delivery across your agent-based system. The dispatch system provides a unified interface for sending signals to various destinations through a plugin-based adapter architecture.

## Key Concepts

- **Adapters**: Pluggable components that implement specific delivery mechanisms
- **Dispatch Configuration**: Declarative routing rules for signals
- **Delivery Modes**: Synchronous and asynchronous delivery options
- **Error Handling**: Comprehensive error management across delivery methods

## Built-in Adapters

Jido provides several built-in adapters for common use cases:

- `pid`: Direct delivery to Erlang processes
- `bus`: Publication to event buses
- `named`: Delivery to named processes
- `pubsub`: Integration with Phoenix.PubSub
- `logger`: Signal logging via Logger
- `console`: Console output for debugging
- `noop`: No-op adapter for testing

## Basic Usage

### Simple Process Delivery

```elixir
# Async delivery to a process
config = {:pid, [
  target: destination_pid,
  delivery_mode: :async
]}

Jido.Signal.Dispatch.dispatch(signal, config)

# Sync delivery with timeout
config = {:pid, [
  target: destination_pid,
  delivery_mode: :sync,
  timeout: 5000
]}

Jido.Signal.Dispatch.dispatch(signal, config)
```

### Multiple Destinations

```elixir
# Send to multiple targets
config = [
  {:bus, [target: :event_bus, stream: "events"]},
  {:logger, [level: :info]},
  {:pubsub, [target: :audit_pubsub, topic: "audit"]}
]

Jido.Signal.Dispatch.dispatch(signal, config)
```

## Adapter Configuration

### PID Adapter

The PID adapter delivers signals directly to Erlang processes:

```elixir
config = {:pid, [
  target: destination_pid,
  delivery_mode: :async,  # or :sync
  timeout: 5000,         # for sync mode
  message_format: &format_message/1  # optional
]}
```

### Bus Adapter

The Bus adapter publishes signals to Jido event buses:

```elixir
config = {:bus, [
  target: :my_bus,
  stream: "default"  # optional, defaults to "default"
]}
```

### Named Process Adapter

The Named adapter delivers to registered processes:

```elixir
config = {:named, [
  target: {:name, :registered_name},
  delivery_mode: :async,  # or :sync
  timeout: 5000          # for sync mode
]}
```

### PubSub Adapter

The PubSub adapter integrates with Phoenix.PubSub:

```elixir
config = {:pubsub, [
  target: :my_pubsub,
  topic: "events"
]}
```

### Logger Adapter

The Logger adapter emits signals through the Logger system:

```elixir
config = {:logger, [
  level: :info,  # :debug, :info, :warning, or :error
  structured: true  # optional, for structured logging
]}
```

## Error Handling

Each adapter provides specific error handling for its delivery mechanism:

```elixir
case Jido.Signal.Dispatch.dispatch(signal, config) do
  :ok ->
    # Signal delivered successfully
    handle_success()

  {:error, :process_not_found} ->
    # Target process not registered
    handle_missing_process()

  {:error, :process_not_alive} ->
    # Target process is dead
    handle_dead_process()

  {:error, :timeout} ->
    # Sync delivery timed out
    handle_timeout()

  {:error, reason} ->
    # Other errors
    handle_error(reason)
end
```

## Custom Adapters

You can create custom adapters by implementing the `Jido.Signal.Dispatch.Adapter` behaviour:

```elixir
defmodule MyApp.CustomAdapter do
  @behaviour Jido.Signal.Dispatch.Adapter

  @impl true
  def validate_opts(opts) do
    # Validate adapter-specific options
    with {:ok, target} <- validate_target(opts[:target]),
         {:ok, mode} <- validate_mode(opts[:mode]) do
      {:ok, opts}
    end
  end

  @impl true
  def deliver(signal, opts) do
    # Implement delivery logic
    try do
      do_deliver(signal, opts)
      :ok
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  # Private helpers
  defp validate_target(target) do
    # Validation logic
  end

  defp validate_mode(mode) do
    # Validation logic
  end

  defp do_deliver(signal, opts) do
    # Delivery implementation
  end
end
```

## Best Practices

### Configuration Management

1. **Validation**: Always validate dispatch configurations early:

```elixir
with {:ok, validated_config} <- Dispatch.validate_opts(config) do
  # Use validated config
end
```

2. **Defaults**: Define sensible defaults for timeout and delivery modes:

```elixir
config = {:pid, [
  target: pid,
  delivery_mode: :async,
  timeout: Application.get_env(:my_app, :default_timeout, 5000)
]}
```

3. **Error Handling**: Implement comprehensive error handling:

```elixir
defmodule MyApp.Dispatcher do
  def safe_dispatch(signal, config) do
    case Dispatch.dispatch(signal, config) do
      :ok ->
        {:ok, :delivered}
      {:error, reason} = error ->
        Logger.error("Dispatch failed: #{inspect(reason)}")
        error
    end
  end
end
```

### Performance Considerations

1. **Async vs Sync**: Use async delivery when possible for better throughput
2. **Timeouts**: Configure appropriate timeouts based on operation complexity
3. **Batching**: Consider batching signals for efficiency when applicable

### Testing

1. **Use NoopAdapter**: For testing without side effects:

```elixir
config = {:noop, []}
```

2. **Test Different Modes**: Cover both sync and async delivery:

```elixir
test "handles sync delivery timeout" do
  config = {:pid, [
    target: slow_process,
    delivery_mode: :sync,
    timeout: 1  # Very short timeout
  ]}

  assert {:error, :timeout} = Dispatch.dispatch(signal, config)
end
```

3. **Mock Custom Adapters**: Use mocks for custom adapters:

```elixir
test "custom adapter delivery" do
  Mock.expect(MyAdapter, :deliver, fn _signal, _opts -> :ok end)
  config = {MyAdapter, [custom_opt: "value"]}

  assert :ok = Dispatch.dispatch(signal, config)
end
```

## Common Patterns

### Fallback Chain

Implement delivery fallbacks for resilience:

```elixir
defmodule MyApp.ResilientDispatcher do
  def dispatch_with_fallback(signal) do
    configs = [
      {:pid, [target: primary_pid()]},
      {:named, [target: {:name, :backup_process}]},
      {:logger, [level: :error]}
    ]

    Enum.reduce_while(configs, {:error, :no_delivery}, fn config, _acc ->
      case Dispatch.dispatch(signal, config) do
        :ok -> {:halt, :ok}
        _error -> {:cont, {:error, :trying_next}}
      end
    end)
  end
end
```

### Broadcast Pattern

Send signals to multiple destinations:

```elixir
defmodule MyApp.Broadcaster do
  def broadcast(signal) do
    config = [
      {:pubsub, [target: :main_pubsub, topic: "events"]},
      {:bus, [target: :audit_bus, stream: "audit"]},
      {:logger, [level: :info, structured: true]}
    ]

    Dispatch.dispatch(signal, config)
  end
end
```

### Conditional Dispatch

Route signals based on content:

```elixir
defmodule MyApp.ConditionalDispatcher do
  def smart_dispatch(signal) do
    config =
      cond do
        urgent?(signal) ->
          {:pid, [target: urgent_handler(), delivery_mode: :sync]}

        audit_required?(signal) ->
          [
            {:pid, [target: handler_pid()]},
            {:pubsub, [target: :audit_pubsub, topic: "audit"]}
          ]

        true ->
          {:pid, [target: default_handler()]}
      end

    Dispatch.dispatch(signal, config)
  end
end
```

## Troubleshooting

### Common Issues

1. **Process Not Found**

   - Ensure processes are registered before dispatch
   - Verify process names are correct
   - Check for timing issues in process startup

2. **Timeouts**

   - Review timeout configurations
   - Check for blocking operations
   - Consider using async mode

3. **Message Format Errors**
   - Verify signal structure
   - Check custom message formatters
   - Ensure serialization compatibility

### Debugging Tips

1. Use the console adapter for visibility:

```elixir
config = [
  {:console, []},
  actual_config
]
```

2. Enable structured logging:

```elixir
config = {:logger, [
  level: :debug,
  structured: true
]}
```

3. Implement telemetry for monitoring:

```elixir
defmodule MyApp.DispatchTelemetry do
  def handle_dispatch(signal, config) do
    start = System.monotonic_time()

    result = Dispatch.dispatch(signal, config)

    duration = System.monotonic_time() - start
    :telemetry.execute(
      [:my_app, :dispatch],
      %{duration: duration},
      %{signal: signal, result: result}
    )

    result
  end
end
```

## See Also

- [Signal Overview](signals/overview.md) - Introduction to signals
- [Signal Bus](signals/bus.md) - Details on the bus system
- [Signal Routing](signals/routing.md) - Signal routing mechanisms
- [Serialization](signals/serialization.md) - Signal serialization guide
