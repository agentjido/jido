defmodule JidoTest.TestSensors do
  defmodule CounterSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "counter_sensor",
      description: "A sensor that emits a counter value at a specified interval",
      category: :counter,
      tags: [:counter, :interval],
      vsn: "1.0.0",
      schema: [
        floor: [type: :integer, default: 0],
        emit_interval: [type: :pos_integer, required: true]
      ]

    def mount(opts) do
      state = Map.put(opts, :counter, opts.floor)
      schedule_emit(state)
      {:ok, state}
    end

    def generate_signal(state) do
      new_counter = state.counter + 1

      {:ok, signal} =
        Jido.Signal.new(%{
          source: "#{state.sensor.name}:#{state.id}",
          subject: "counter",
          type: "counter",
          data: %{value: new_counter},
          timestamp: DateTime.utc_now()
        })

      {:ok, signal, %{state | counter: new_counter}}
    end

    def handle_info(:emit, state) do
      case generate_signal(state) do
        {:ok, signal, new_state} ->
          publish_signal(signal, new_state)
          schedule_emit(new_state)
          {:noreply, new_state}

          # {:error, reason} ->
          #   Logger.warning("Error generating signal: #{inspect(reason)}")
          #   schedule_emit(state)
          #   {:noreply, state}
      end
    end

    defp schedule_emit(state) do
      Process.send_after(self(), :emit, state.emit_interval)
    end
  end
end
