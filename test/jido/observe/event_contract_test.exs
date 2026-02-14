defmodule JidoTest.Observe.EventContractTest do
  use ExUnit.Case, async: true

  alias Jido.Observe.EventContract

  describe "validate_metadata/2" do
    test "returns ok when all required keys exist" do
      metadata = %{request_id: "req-1", state: :completed}

      assert {:ok, ^metadata} =
               EventContract.validate_metadata(metadata, [:request_id, :state])
    end

    test "returns missing metadata keys in deterministic order" do
      metadata = %{request_id: "req-1"}

      assert {:error, {:missing_metadata_keys, [:state, :model]}} =
               EventContract.validate_metadata(metadata, [:request_id, :state, :model])
    end

    test "treats atom required keys as present when metadata uses string keys" do
      metadata = %{"request_id" => "req-1", "state" => "completed"}

      assert {:ok, ^metadata} =
               EventContract.validate_metadata(metadata, [:request_id, :state])
    end
  end

  describe "validate_measurements/2" do
    test "returns ok when all required keys exist" do
      measurements = %{duration_ms: 12, token_count: 40}

      assert {:ok, ^measurements} =
               EventContract.validate_measurements(measurements, [:duration_ms, :token_count])
    end

    test "returns missing measurement keys in deterministic order" do
      measurements = %{duration_ms: 12}

      assert {:error, {:missing_measurement_keys, [:token_count, :attempt]}} =
               EventContract.validate_measurements(measurements, [
                 :duration_ms,
                 :token_count,
                 :attempt
               ])
    end
  end

  describe "validate_event/4" do
    test "returns normalized event payload when contract is valid" do
      event = [:jido, :ai, :request, :completed]
      measurements = %{duration_ms: 45}
      metadata = %{request_id: "req-1", terminal_state: :completed}

      assert {:ok, %{event: ^event, measurements: ^measurements, metadata: ^metadata}} =
               EventContract.validate_event(event, measurements, metadata,
                 required_metadata: [:request_id, :terminal_state],
                 required_measurements: [:duration_ms]
               )
    end

    test "returns combined missing keys for invalid contracts" do
      event = [:jido, :ai, :request, :failed]
      measurements = %{}
      metadata = %{request_id: "req-1"}

      assert {:error,
              {:invalid_event_contract,
               %{
                 event: ^event,
                 missing_metadata_keys: [:terminal_state],
                 missing_measurement_keys: [:duration_ms]
               }}} =
               EventContract.validate_event(event, measurements, metadata,
                 required_metadata: [:request_id, :terminal_state],
                 required_measurements: [:duration_ms]
               )
    end
  end
end
