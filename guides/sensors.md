# Signals and Sensors

In our previous guides, we explored how Actions serve as composable building blocks and how Agents provide stateful wrappers around them. Now, let's discover how Signals and Sensors enable real-time event monitoring and metrics collection in your Jido system.

## Understanding Signals and Sensors

Before we dive into code, let's understand what Signals and Sensors are and why they're important in a distributed system.

### What are Signals?

At their core, Signals are standardized event messages that flow through your Jido system. They implement the CloudEvents specification (v1.0.2) with Jido-specific extensions, providing a consistent format for all system events. Think of Signals as the nervous system of your application - they carry information about:

- State changes
- Metric updates
- System events
- Process lifecycle events
- Command execution results

Every Signal includes standard CloudEvents fields like:
- `id`: A unique identifier
- `source`: Where the signal originated
- `type`: What kind of event it represents
- `subject`: What entity the signal relates to
- `data`: The actual event payload

Plus Jido-specific fields for:
- `jidoinstructions`: Instructions for the Agent to execute
- `jidoopts`: Options for signal processing

### Why Sensors?

Sensors are independent GenServer processes that gather external information and update agent state independently. This architectural choice is crucial for distributed systems where a single agent might have dozens of sensors feeding it information simultaneously - from API monitoring and metrics tracking to event stream processing.

Running sensors as standalone processes under OTP supervision provides key benefits:
- **Fault Isolation**: A failing sensor won't crash the agent or other sensors
- **Independent Scaling**: Sensors can be distributed across nodes based on load
- **Resource Management**: Each sensor manages its own memory and process queue
- **Dynamic Operation**: Sensors can be started, stopped, and supervised independently

While this guide covers defining and starting individual sensors, later guides will explain how agents dynamically manage multiple sensors through registration, lifecycle management, and event routing.

Sensors serve several purposes:
- Track metrics and state changes in real-time
- Process and aggregate event streams
- Generate alerts for important conditions
- Maintain recent event history

A key role of Sensors is translating external events into standardized Signals that agents can understand and consume. For example, a sensor might:
- Listen for HTTP webhook events and emit corresponding agent-ready signals
- Watch a message queue and transform messages into signals
- Monitor file changes and generate file-event signals
- Subscribe to external event streams and normalize them into signals

Think of sensors as specialized translators that convert various external events into a consistent Signal format that agents know how to process, all while operating independently under OTP supervision.

## Creating Your First Sensor

Let's build on our user registration example by creating a Sensor that monitors registration success rates. This will help us understand usage patterns and identify potential issues.

```elixir
defmodule MyApp.Sensors.RegistrationCounter do
  @moduledoc """
  Tracks user registration success and failure metrics.
  """
  use Jido.Sensor,
    name: "registration_counter",
    description: "Monitors registration successes and failures",
    category: :metrics,
    tags: [:registration, :counter],
    vsn: "1.0.0",
    schema: [
      emit_interval: [
        type: :pos_integer,
        default: 1000,
        doc: "Interval between metric emissions in ms"
      ]
    ]

  def mount(opts) do
    state = Map.merge(opts, %{
      successful: 0,
      failed: 0
    })
    
    schedule_emit(state)
    {:ok, state}
  end

  def generate_signal(state) do
    total = state.successful + state.failed
    success_rate = if total > 0, do: state.successful / total * 100, else: 0

    Jido.Signal.new(%{
      source: "#{state.sensor.name}:#{state.id}",
      subject: "registration_counts",
      type: "registration.metrics",
      data: %{
        successful: state.successful,
        failed: state.failed,
        total: total,
        success_rate: success_rate
      }
    })
  end

  def handle_info(:emit, state) do
    with {:ok, signal} <- generate_signal(state),
         :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal}) do
      schedule_emit(state)
      {:noreply, state}
    else
      error ->
        Logger.warning("Error generating/publishing signal: #{inspect(error)}")
        schedule_emit(state)
        {:noreply, state}
    end
  end

  def handle_info({:registration, :success}, state) do
    new_state = %{state | successful: state.successful + 1}
    
    with {:ok, signal} <- generate_signal(new_state),
         :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal}) do
      {:noreply, new_state}
    else
      error ->
        Logger.warning("Error broadcasting success signal: #{inspect(error)}")
        {:noreply, new_state}
    end
  end

  def handle_info({:registration, :failure}, state) do
    new_state = %{state | failed: state.failed + 1}
    
    with {:ok, signal} <- generate_signal(new_state),
         :ok <- Phoenix.PubSub.broadcast(state.pubsub, state.topic, {:sensor_signal, signal}) do
      {:noreply, new_state}
    else
      error ->
        Logger.warning("Error broadcasting failure signal: #{inspect(error)}")
        {:noreply, new_state}
    end
  end

  defp schedule_emit(state) do
    Process.send_after(self(), :emit, state.emit_interval)
  end
end
```

Let's break down what's happening in this Sensor:

1. We use `use Jido.Sensor` to define our Sensor, providing metadata like:
   - `name`: Unique identifier
   - `description`: What the Sensor monitors
   - `category`: Classification for grouping
   - `tags`: Labels for filtering
   - `schema`: Configuration options

2. The `mount/1` callback initializes our Sensor's state with:
   - Counters for successes and failures
   - Configuration from schema
   - Scheduled metric emissions

3. `generate_signal/1` creates standardized Signal structs containing:
   - Current metric values
   - Calculated success rate
   - Source identification
   - Event type and subject

4. Message handlers track events and emit signals:
   - `:emit` for regular metric updates
   - `{:registration, :success}` for successful registrations
   - `{:registration, :failure}` for failed registrations

## Working with Signals

Signals provide a standardized way to represent events in your system. Let's look at how to create and handle them:

### Creating Signals

The simplest way to create a Signal is using `Jido.Signal.new/1`:

```elixir
{:ok, signal} = Jido.Signal.new(%{
  source: "my_component",
  type: "user.registered",
  subject: "user_123",
  data: %{
    username: "john.doe",
    timestamp: DateTime.utc_now()
  }
})
```

Signals are validated to ensure they contain required fields and follow the CloudEvents spec.

### Publishing Signals

Signals are typically published through Phoenix.PubSub:

```elixir
Phoenix.PubSub.broadcast(pubsub, topic, signal)
```

The signal will be received directly by any subscribers to that topic.

### Subscribing to Signals

To receive Signals, subscribe to the relevant PubSub topic:

```elixir
Phoenix.PubSub.subscribe(pubsub, "registration_counter")

# In your process's handle_info:
def handle_info(%Signal{} = signal, state) do
  # Process the signal
  Logger.info("Received signal: #{signal.type} with data: #{inspect(signal.data)}")
  {:noreply, state}
end
```

## Testing Sensors and Signals

For a complete example of how to test Sensors and Signals, refer to the registration counter test suite in `test/jido/sensor/examples/user_registration_sensor_test.exs`. This comprehensive test suite demonstrates:

1. Setting up test PubSub environments
2. Testing event counting and metric calculations
3. Verifying signal emissions and formats
4. Handling timing-dependent behavior

The test patterns shown there can be adapted for testing your own Sensors.

## Best Practices

When working with Signals and Sensors, keep these principles in mind:

1. **Signal Design**
   - Use clear, consistent signal types
   - Include enough context in payloads
   - Follow the CloudEvents spec
   - Keep payloads focused and minimal

2. **Sensor Implementation**
   - One responsibility per Sensor
   - Clear configuration through schema
   - Efficient state management
   - Graceful error handling

3. **Testing**
   - Test both success and failure paths
   - Verify metric calculations
   - Check signal formats
   - Test timing-dependent behavior

4. **Performance**
   - Use appropriate emission intervals
   - Batch updates when possible
   - Monitor memory usage
   - Clean up old data

## Integration with Agents

Signals and Sensors lay the groundwork for advanced agent capabilities by providing:

1. **Real-time Metrics**: Agents can use sensor data to make informed decisions
2. **Event Streams**: Agents can react to system events through signals
3. **Status Updates**: Agents can monitor each other's health
4. **Command Results**: Agents can track the results of their actions

In the next guide, we'll explore how Server Agents use these signals for coordination and decision-making.

## Next Steps

Now that you understand Signals and Sensors, you can explore:
- Custom signal types
- Complex metric calculations
- Event stream processing
- Multi-sensor coordination
- Integration with monitoring systems
- Historical analysis

The test suite provides many examples of these patterns in action.

Remember: Signals and Sensors are your eyes and ears in the system. Design them thoughtfully to give your agents the information they need to make smart decisions.