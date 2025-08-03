defmodule Jido.Sensors.Heartbeat do
  @moduledoc """
  A sensor that emits heartbeat signals at configurable intervals.
  """
  use Jido.Sensor,
    name: "heartbeat_sensor",
    description: "Emits heartbeat signals at configurable intervals",
    category: :system,
    tags: [:heartbeat, :monitoring],
    vsn: "1.0.0",
    schema: [
      interval: [
        type: :pos_integer,
        default: 5000,
        doc: "Interval between heartbeats in milliseconds"
      ],
      message: [
        type: :string,
        default: "heartbeat",
        doc: "Message to include in heartbeat signal"
      ]
    ]

  @impl true
  def mount(opts) do
    state = %{
      id: opts.id,
      target: opts.target,
      sensor: %{name: "heartbeat_sensor"},
      config: %{
        interval: opts.interval,
        message: opts.message
      },
      last_beat: DateTime.utc_now()
    }

    schedule_heartbeat(state.config.interval)
    {:ok, state}
  end

  @impl true
  @spec deliver_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}
  def deliver_signal(state) do
    now = DateTime.utc_now()

    Jido.Signal.new(%{
      source: "#{state.sensor.name}:#{state.id}",
      type: "heartbeat",
      data: %{
        message: state.config.message,
        timestamp: now,
        last_beat: state.last_beat
      }
    })
  end

  @impl GenServer
  def handle_info(:heartbeat, state) do
    now = DateTime.utc_now()

    case deliver_signal(state) do
      {:ok, signal} ->
        case Jido.Signal.Dispatch.dispatch(signal, state.target) do
          :ok ->
            schedule_heartbeat(state.config.interval)
            {:noreply, %{state | last_beat: now}}

          {:error, reason} ->
            require Logger
            Logger.warning("Error delivering heartbeat signal: #{inspect(reason)}")
            schedule_heartbeat(state.config.interval)
            {:noreply, state}
        end

      {:error, reason} ->
        require Logger
        Logger.warning("Error creating heartbeat signal: #{inspect(reason)}")
        schedule_heartbeat(state.config.interval)
        {:noreply, state}
    end
  end

  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end
end
