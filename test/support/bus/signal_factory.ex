defmodule JidoTest.Helpers.SignalFactory do
  @moduledoc false
  alias Jido.Bus.RecordedSignal
  alias Jido.Signal

  def map_to_recorded_signals(signals, initial_signal_number \\ 1, opts \\ []) do
    stream_id = UUID.uuid4()
    jido_causation_id = Keyword.get(opts, :jido_causation_id, UUID.uuid4())
    jido_correlation_id = Keyword.get(opts, :jido_correlation_id, UUID.uuid4())
    metadata = Keyword.get(opts, :metadata, %{})

    fields = [
      jido_causation_id: jido_causation_id,
      jido_correlation_id: jido_correlation_id,
      metadata: metadata
    ]

    signals
    |> Signal.map_to_signal_data(fields)
    |> Enum.with_index(initial_signal_number)
    |> Enum.map(fn {signal, index} ->
      %RecordedSignal{
        signal_id: UUID.uuid4(),
        signal_number: index,
        stream_id: stream_id,
        stream_version: index,
        jido_causation_id: signal.jido_causation_id,
        jido_correlation_id: signal.jido_correlation_id,
        type: signal.type,
        data: signal.data,
        metadata: signal.metadata,
        created_at: DateTime.utc_now()
      }
    end)
  end
end
