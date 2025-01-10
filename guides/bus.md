# Signal Bus

In our previous guides, we explored how Actions provide composable building blocks, how Agents manage state, and how Signals enable real-time monitoring. Now, let's discover how the Signal Bus ties these components together by providing a robust messaging infrastructure.

## Understanding the Signal Bus

At its core, the Jido Signal Bus is a message routing and persistence system that enables:
- Publishing and subscribing to signal streams
- Persistent message storage and replay
- Real-time signal distribution
- State snapshots for recovery
- Flexible adapter architecture

Think of the Signal Bus as the nervous system of your Jido application - it ensures signals flow reliably between components while maintaining message ordering and persistence guarantees.

### Key Concepts

The Signal Bus is built around several key abstractions:

1. **Signals**: Standardized message format following CloudEvents spec
2. **Streams**: Ordered sequences of signals
3. **Subscriptions**: Ways to consume signals (transient or persistent)
4. **Snapshots**: Point-in-time state captures
5. **Adapters**: Pluggable backend implementations

## Getting Started

Let's see how to use the Signal Bus in practice:

```elixir
# Start the bus with an in-memory adapter
children = [
  {Jido.Bus, name: :my_bus, adapter: :in_memory}
]

# Or with Phoenix.PubSub for distributed scenarios
children = [
  {Jido.Bus, name: :my_bus, adapter: :pubsub, pubsub_name: MyApp.PubSub}
]
```

### Publishing Signals

Signals can be published to named streams:

```elixir
signal = %Jido.Signal{
  id: UUID.uuid4(),
  source: "user_service",
  type: "user.registered",
  data: %{user_id: "123", email: "user@example.com"},
  metadata: %{client_ip: "127.0.0.1"}
}

:ok = Jido.Bus.publish(:my_bus, "user_stream", :any_version, [signal])
```

The `:any_version` parameter tells the bus to append without checking versions. You can also use:
- `:no_stream` - Requires stream doesn't exist
- `:stream_exists` - Requires stream exists
- Integer version - Requires exact version match

### Subscribing to Signals

The bus supports two types of subscriptions:

#### 1. Transient Subscriptions
Best for temporary subscribers that don't need persistence:

```elixir
# Subscribe to a single stream
:ok = Jido.Bus.subscribe(:my_bus, "user_stream")

# Receive signals
receive do
  {:signals, signals} -> 
    Enum.each(signals, &process_signal/1)
end
```

#### 2. Persistent Subscriptions
For durable subscribers that need guaranteed delivery:

```elixir
{:ok, subscription} = Jido.Bus.subscribe_persistent(
  :my_bus,                # Bus name
  "user_stream",          # Stream to subscribe to
  "user_processor",       # Subscription name
  self(),                # Subscriber pid
  :origin,               # Start from beginning
  [                      # Options
    concurrency_limit: 2,
    partition_by: &partition_function/1
  ]
)

# Receive signals and acknowledge processing
receive do
  {:signals, signals} ->
    process_signals(signals)
    Jido.Bus.ack(:my_bus, subscription, List.last(signals))
end
```

The subscription options include:
- `:origin` - Start from beginning
- `:current` - Start from now
- Integer position - Start from specific point
- `concurrency_limit` - Max concurrent subscribers
- `partition_by` - Function to partition signals

### Replaying Signals

The bus supports replaying historical signals:

```elixir
# Replay all signals from start
signals = Jido.Bus.replay(:my_bus, "user_stream")

# Replay from specific version
signals = Jido.Bus.replay(:my_bus, "user_stream", 100)

# Control batch size
signals = Jido.Bus.replay(:my_bus, "user_stream", 100, 50)

Enum.each(signals, &process_signal/1)
```

### Working with Snapshots

Snapshots provide point-in-time state capture:

```elixir
# Record a snapshot
snapshot = %Jido.Bus.Snapshot{
  source_id: "user_123",
  source_version: 50,
  source_type: "UserAggregate",
  data: serialize_state(current_state),
  created_at: DateTime.utc_now()
}

:ok = Jido.Bus.record_snapshot(:my_bus, snapshot)

# Read snapshot
{:ok, snapshot} = Jido.Bus.read_snapshot(:my_bus, "user_123")

# Delete snapshot
:ok = Jido.Bus.delete_snapshot(:my_bus, "user_123")
```

## Bus Adapters

The Signal Bus supports multiple backend adapters:

### In-Memory Adapter
Best for development and testing:
- Full persistence and replay support
- Fast local operation
- Memory-bound storage
- No distribution

```elixir
{Jido.Bus, name: :my_bus, adapter: :in_memory}
```

### PubSub Adapter
Best for distributed scenarios:
- Built on Phoenix.PubSub
- Supports clustering
- Real-time message distribution
- No persistence/replay

```elixir
{Jido.Bus, name: :my_bus, adapter: :pubsub, pubsub_name: MyApp.PubSub}
```

