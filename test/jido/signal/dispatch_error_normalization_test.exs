defmodule Jido.Signal.DispatchErrorNormalizationTest do
  use ExUnit.Case, async: true
  alias Jido.Signal.Dispatch
  alias Jido.Signal
  alias Jido.Error

  # Test with error normalization enabled per test

  test "dispatch normalizes errors to Jido.Error when enabled" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    # Use PID adapter with dead process
    {:ok, pid} = Agent.start(fn -> :ok end)
    Agent.stop(pid)

    config = {:pid, [target: pid, delivery_mode: :async]}

    result = Dispatch.dispatch(signal, config)

    assert {:error, %Error{type: :dispatch_error}} = result
    {:error, error} = result

    assert error.message == "Dispatch failed: process_not_alive"
    assert error.details.adapter == :pid
    assert error.details.reason == :process_not_alive
    assert error.details.config == config

    # Clean up
    Application.delete_env(:jido, :normalize_dispatch_errors)
  end

  test "dispatch_batch normalizes errors when enabled" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    configs = [
      # This should succeed
      {:noop, []},
      # This should fail
      {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}
    ]

    result = Dispatch.dispatch_batch(signal, configs, [])

    assert {:error, [{1, %Error{type: :dispatch_error}}]} = result
    {:error, [{1, error}]} = result

    assert error.message == "Dispatch failed: process_not_found"
    assert error.details.adapter == :named
    assert error.details.reason == :process_not_found

    # Clean up
    Application.delete_env(:jido, :normalize_dispatch_errors)
  end

  test "telemetry events are emitted with correct metadata" do
    # Set up telemetry handler
    test_pid = self()
    handler_id = :dispatch_test_handler

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :dispatch, :start],
        [:jido, :dispatch, :stop],
        [:jido, :dispatch, :exception]
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    config = {:noop, []}

    # Successful dispatch
    assert :ok = Dispatch.dispatch(signal, config)

    # Should receive start and stop events
    assert_receive {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert metadata.adapter == :noop
    assert metadata.signal_type == "test.event"
    assert metadata.target == :unknown

    assert_receive {:telemetry, [:jido, :dispatch, :stop], measurements, metadata}
    assert Map.has_key?(measurements, :latency_ms)
    assert metadata.success? == true

    # Failed dispatch
    {:ok, pid} = Agent.start(fn -> :ok end)
    Agent.stop(pid)
    config = {:pid, [target: pid, delivery_mode: :async]}

    {:error, _} = Dispatch.dispatch(signal, config)

    # Should receive start and exception events
    assert_receive {:telemetry, [:jido, :dispatch, :start], %{}, _}
    assert_receive {:telemetry, [:jido, :dispatch, :exception], measurements, metadata}
    assert Map.has_key?(measurements, :latency_ms)
    assert metadata.success? == false

    :telemetry.detach(handler_id)
  end
end
