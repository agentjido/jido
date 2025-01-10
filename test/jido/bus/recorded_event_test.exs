defmodule Jido.Bus.RecordedSignalTest do
  use ExUnit.Case

  alias Jido.Bus.RecordedSignal
  alias JidoTest.Helpers.SignalFactory

  defmodule BankAccountOpened do
    @derive Jason.Encoder
    defstruct [:account_number, :initial_balance]
  end

  setup do
    [signal] =
      SignalFactory.map_to_recorded_signals(
        [
          %BankAccountOpened{account_number: "123", initial_balance: 1_000}
        ],
        1,
        metadata: %{"key1" => "value1", "key2" => "value2"}
      )

    [signal: signal]
  end

  describe "RecordedSignal struct" do
    test "enrich_metadata/2 should add a number of fields to the metadata", %{signal: signal} do
      %RecordedSignal{
        signal_id: signal_id,
        signal_number: signal_number,
        stream_id: stream_id,
        stream_version: stream_version,
        jido_correlation_id: jido_correlation_id,
        jido_causation_id: jido_causation_id,
        created_at: created_at
      } = signal

      enriched_metadata =
        RecordedSignal.enrich_metadata(signal,
          additional_metadata: %{
            application: ExampleApplication
          }
        )

      assert enriched_metadata == %{
               # Signal string-keyed metadata
               "key1" => "value1",
               "key2" => "value2",
               # Standard signal fields
               signal_id: signal_id,
               signal_number: signal_number,
               stream_id: stream_id,
               stream_version: stream_version,
               jido_correlation_id: jido_correlation_id,
               jido_causation_id: jido_causation_id,
               created_at: created_at,
               # Additional field
               application: ExampleApplication
             }
    end

    test "map_from_recorded_signal/1 extracts the data from a recorded signal", %{signal: signal} do
      expected_data = %BankAccountOpened{account_number: "123", initial_balance: 1_000}
      assert RecordedSignal.map_from_recorded_signal(signal) == expected_data
    end
  end
end
