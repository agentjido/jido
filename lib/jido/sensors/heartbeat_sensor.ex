defmodule Jido.Sensors.Heartbeat do
  @moduledoc """
  A sensor that emits heartbeat signals at configurable intervals.

  ## Configuration

  - `interval` - Interval between heartbeats in milliseconds (default: 5000)
  - `message` - Message to include in heartbeat signal (default: "heartbeat")

  ## Example

      # Start via SensorServer
      {:ok, pid} = Jido.Sensor.Runtime.start_link(
        sensor: Jido.Sensors.Heartbeat,
        config: %{interval: 1000, message: "alive"}
      )
  """
  use Jido.Sensor,
    name: "heartbeat",
    description: "Emits heartbeat signals at configurable intervals",
    schema:
      Zoi.object(
        %{
          interval:
            Zoi.integer(description: "Interval between heartbeats in milliseconds")
            |> Zoi.default(5000),
          message:
            Zoi.string(description: "Message to include in heartbeat signal")
            |> Zoi.default("heartbeat")
        },
        coerce: true
      )

  @impl Jido.Sensor
  def init(config, context) do
    state = %{
      target: context[:agent_ref],
      interval: config.interval,
      message: config.message
    }

    {:ok, state, [{:schedule, config.interval}]}
  end

  @impl Jido.Sensor
  def handle_event(:tick, state) do
    now = DateTime.utc_now()

    signal =
      Jido.Signal.new!(%{
        source: "/sensor/heartbeat",
        type: "jido.sensor.heartbeat",
        data: %{
          message: state.message,
          timestamp: now
        }
      })

    {:ok, state, [{:emit, signal}, {:schedule, state.interval}]}
  end
end
