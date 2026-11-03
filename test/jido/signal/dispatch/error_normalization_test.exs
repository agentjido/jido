defmodule Jido.Signal.Dispatch.ErrorNormalizationTest do
  use ExUnit.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias Jido.Signal.Error
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Trace

  # Named function for telemetry handler to avoid performance warnings
  def handle_telemetry_event(event, measurements, metadata, _config) do
    # Get the test pid from the metadata or use a default
    test_pid = Process.get(:test_pid) || self()
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  defmodule CrashingAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def options_schema, do: Jido.Joi.keyword([], unrecognized_keys: :error)

    @impl true
    def deliver(_signal, _opts), do: raise("adapter crashed")
  end

  defmodule URLReportingAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def options_schema do
      Jido.Joi.keyword(
        [
          url: Jido.Joi.string() |> Jido.Joi.required(),
          headers: Jido.Joi.list() |> Jido.Joi.optional(),
          secret: Jido.Joi.string() |> Jido.Joi.optional()
        ],
        unrecognized_keys: :error
      )
    end

    @impl true
    def deliver(_signal, _opts), do: {:error, :not_sent}
  end

  defmodule TargetReportingAdapter do
    @behaviour Jido.Signal.Dispatch.Adapter

    @impl true
    def options_schema do
      Jido.Joi.keyword([target: Jido.Joi.any() |> Jido.Joi.required()], unrecognized_keys: :error)
    end

    @impl true
    def deliver(_signal, _opts), do: {:error, :not_sent}
  end

  setup do
    Application.delete_env(:jido, :normalize_dispatch_errors)

    on_exit(fn ->
      Application.delete_env(:jido, :normalize_dispatch_errors)
    end)

    :ok
  end

  # Test with error normalization enabled per test

  test "dispatch normalizes errors to Jido.Signal.Error when enabled" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    # Use PID adapter with dead process
    {:ok, pid} = Agent.start(fn -> :ok end)
    Agent.stop(pid)

    config = {:pid, [target: pid, delivery_mode: :async]}

    result = Dispatch.dispatch(signal, config)

    assert {:error, %Error.DispatchError{}} = result
    {:error, error} = result

    assert Exception.message(error) =~ "Signal dispatch failed"
  end

  test "multi-target dispatch normalizes errors when enabled" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    configs = [
      # This should succeed
      {:noop, []},
      # This should fail
      {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}
    ]

    result = Dispatch.dispatch(signal, configs)

    assert {:error, [%Error.DispatchError{}]} = result
    {:error, [error]} = result

    assert Exception.message(error) =~ "Signal dispatch failed"
  end

  test "telemetry events are emitted with correct metadata" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)

    # Set up telemetry handler
    test_pid = self()
    handler_id = {__MODULE__, test_pid, make_ref()}

    # Store the test pid in process dictionary for the handler to access
    Process.put(:test_pid, test_pid)

    :telemetry.attach_many(
      handler_id,
      [
        [:jido, :dispatch, :start],
        [:jido, :dispatch, :stop],
        [:jido, :dispatch, :exception]
      ],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    trace = Trace.new(trace_flags: "01")
    {:ok, signal} = SignalContext.put_trace(signal, trace)
    config = {:noop, []}

    # Successful dispatch
    assert :ok = Dispatch.dispatch(signal, config)

    # Should receive start and stop events
    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert metadata.adapter == :noop
    assert metadata.signal_type == "test.event"
    assert metadata.target == :unknown
    assert metadata.target_kind == :unknown
    assert metadata.runtime_surface == :dispatch
    assert metadata.jido_trace_id == trace.trace_id
    assert metadata.jido_span_id == trace.span_id
    assert metadata.jido_trace_flags == "01"

    assert_received {:telemetry, [:jido, :dispatch, :stop], measurements, metadata}
    assert Map.has_key?(measurements, :latency_ms)
    assert metadata.success? == true
    assert metadata.outcome == :ok

    # Failed dispatch
    {:ok, pid} = Agent.start(fn -> :ok end)
    Agent.stop(pid)
    config = {:pid, [target: pid, delivery_mode: :async]}

    {:error, _} = Dispatch.dispatch(signal, config)

    # Should receive start and exception events for handled dispatch failures
    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, _}
    assert_received {:telemetry, [:jido, :dispatch, :exception], measurements, metadata}
    assert Map.has_key?(measurements, :latency_ms)
    assert metadata.success? == false
    assert metadata.outcome == :error
    assert metadata.error_type == :dispatch_error
    assert metadata.retryable? == false
  end

  test "dispatch start telemetry redacts URL credentials and query strings" do
    test_pid = self()
    handler_id = {__MODULE__, :url_target_redaction, test_pid}

    Process.put(:test_pid, test_pid)

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :start],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    config = {URLReportingAdapter, [url: "https://user:pass@example.com/path?token=secret"]}

    assert {:error, _reason} = Dispatch.dispatch(signal, config)

    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert metadata.target == "https://example.com"
    assert metadata.target_kind == :url
  end

  test "dispatch start telemetry marks an invalid URL without reporting its text" do
    test_pid = self()
    handler_id = {__MODULE__, :invalid_url_target, test_pid}
    Process.put(:test_pid, test_pid)

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :start],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    invalid_url = "not a URL with secret text"

    assert {:error, :not_sent} =
             Dispatch.dispatch(signal, {URLReportingAdapter, url: invalid_url})

    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert metadata.target == :invalid_url
    assert metadata.target_kind == :url
    refute inspect(metadata) =~ invalid_url
  end

  test "structured dispatch errors do not contain target credentials" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    config =
      {URLReportingAdapter,
       url: "https://example.com/path?token=url-secret",
       headers: [{"authorization", "Bearer header-secret"}],
       secret: "adapter-secret"}

    assert {:error, %Error.DispatchError{} = error} = Dispatch.dispatch(signal, config)

    error_text = inspect(error.details)
    assert error_text =~ "https://example.com"
    refute error_text =~ "/path"
    refute error_text =~ "url-secret"
    refute error_text =~ "header-secret"
    refute error_text =~ "adapter-secret"
  end

  test "bounds custom targets in telemetry and structured errors" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    test_pid = self()
    handler_id = {__MODULE__, :bounded_target, test_pid}
    Process.put(:test_pid, test_pid)

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :start],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    target = "secret-" <> String.duplicate("x", 100_000)

    assert {:error, %Error.DispatchError{} = error} =
             Dispatch.dispatch(signal, {TargetReportingAdapter, target: target})

    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert byte_size(metadata.target) <= 163
    assert byte_size(inspect(error.details.target)) < 1_000
    refute inspect(error.details.target) =~ target
  end

  test "invalid dispatch configuration errors contain only the input shape" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)

    assert {:error, %Error.InvalidInputError{} = error} =
             Dispatch.validate_opts(%{authorization: "Bearer config-secret"})

    assert error.value == %{type: :map, size: 1}
    refute inspect(error) =~ "config-secret"
  end

  test "bounds Signal targets in actual Dispatch metadata" do
    handler_id = {__MODULE__, :signal_target, self()}

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :start],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    signal = Signal.new!(type: "test.event", source: "/test")
    target = Signal.new!(id: String.duplicate("i", 100_000), type: "target", source: "/target")

    assert {:error, :not_sent} =
             Dispatch.dispatch(signal, {TargetReportingAdapter, target: target})

    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert byte_size(metadata.target.id) <= 163
    assert metadata.target.type == "target"
  end

  test "bounds Signal types and custom URL origins in actual metadata and errors" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    handler_id = {__MODULE__, :bounded_fields, self()}

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :start],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    signal = Signal.new!(type: String.duplicate("t", 100_000), source: "/test")
    url = "https://" <> String.duplicate("h", 100_000) <> "/secret?token=hidden"

    assert {:error, %Error.DispatchError{} = error} =
             Dispatch.dispatch(signal, {URLReportingAdapter, url: url})

    assert_received {:telemetry, [:jido, :dispatch, :start], %{}, metadata}
    assert byte_size(metadata.signal_type) <= 163
    assert byte_size(metadata.target) <= 163
    refute metadata.target =~ "hidden"
    assert byte_size(error.details.target.target) <= 163
  end

  test "invalid dispatch configuration reports each input shape" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)

    inputs_and_shapes = [
      {[[:invalid]], %{type: :list, count: 1}},
      {{:invalid}, %{type: :tuple, size: 1}},
      {"invalid", %{type: :binary, bytes: 7}},
      {:invalid, %{type: :atom}},
      {42, %{type: :number}},
      {self(), %{type: :other}}
    ]

    for {input, shape} <- inputs_and_shapes do
      assert {:error, %Error.InvalidInputError{value: ^shape}} = Dispatch.validate_opts(input)
    end
  end

  test "dispatch leaves raw adapter reasons unchanged by default" do
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    config = {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}

    assert {:error, :process_not_found} = Dispatch.dispatch(signal, config)
  end

  test "reports improper list shapes without reading their values" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    signal = Signal.new!("dispatch.invalid", %{}, source: "/test")
    invalid = [:invalid | "tail-secret"]

    assert {:error, %Error.InvalidInputError{value: %{type: :improper_list}} = error} =
             Dispatch.validate_opts(invalid)

    refute inspect(error) =~ "tail-secret"
    assert {:error, %Error.InvalidInputError{}} = Dispatch.dispatch(signal, invalid)
    assert {:error, %Error.InvalidInputError{}} = Dispatch.validate_opts([invalid])
    assert {:error, [%Error.InvalidInputError{}]} = Dispatch.dispatch(signal, [invalid])
  end

  test "dispatch reads the consolidated normalization config" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})
    config = {:named, [target: {:name, :nonexistent_process}, delivery_mode: :async]}

    assert {:error, %Error.DispatchError{}} = Dispatch.dispatch(signal, config)
  end

  test "adapter crashes emit safe telemetry and still escape the dispatch boundary" do
    Application.put_env(:jido, :normalize_dispatch_errors, true)
    {:ok, signal} = Signal.new(%{type: "test.event", source: "test", data: %{value: 42}})

    test_pid = self()
    handler_id = {__MODULE__, :adapter_crash, test_pid}
    Process.put(:test_pid, test_pid)

    :telemetry.attach(
      handler_id,
      [:jido, :dispatch, :exception],
      &__MODULE__.handle_telemetry_event/4,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert_raise RuntimeError, "adapter crashed", fn ->
      Dispatch.dispatch(signal, {CrashingAdapter, []})
    end

    assert_received {:telemetry, [:jido, :dispatch, :exception], measurements, metadata}
    assert is_integer(measurements.latency_ms)
    assert metadata.outcome == :raised
    assert metadata.success? == false
    assert metadata.error_type == :dispatch_error
    assert metadata.retryable? == false
    assert metadata.exception_kind == :error
    assert metadata.exception_module == RuntimeError
    refute inspect(metadata) =~ "adapter crashed"
  end
end
