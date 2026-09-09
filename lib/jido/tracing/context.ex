defmodule Jido.Tracing.Context do
  @moduledoc """
  Process-level trace context management for signal tracing.

  Stores trace context in the process dictionary and provides functions
  for propagating trace information across signal processing boundaries.
  """

  alias Jido.Signal
  alias Jido.Telemetry.OpenTelemetry
  alias Jido.Tracing.Trace

  @context_key {:jido, :trace_context}
  @otel_restore_key {:jido, :opentelemetry_restore_context}

  defmodule Captured do
    @moduledoc false

    @enforce_keys [:trace, :otel_context]
    defstruct [:trace, :otel_context]

    @type t :: %__MODULE__{trace: map() | nil, otel_context: term() | nil}
  end

  @doc """
  Ensures trace context exists from a signal.

  If the signal has trace data, stores it in the process dictionary.
  If not, creates a new root trace and stores it.

  Returns `{traced_signal, trace_context}` where traced_signal has trace data attached.
  """
  @spec ensure_from_signal(Signal.t()) :: {Signal.t(), map()}
  def ensure_from_signal(%Signal{} = signal) do
    case Trace.get(signal) do
      nil ->
        trace = Trace.new_root()
        Process.put(@context_key, trace)
        replace_open_telemetry_context(trace)

        case Trace.put(signal, trace) do
          {:ok, traced_signal} -> {traced_signal, trace}
          {:error, _} -> {signal, trace}
        end

      trace ->
        Process.put(@context_key, trace)
        replace_open_telemetry_context(trace)
        {signal, trace}
    end
  end

  @doc """
  Sets trace context from a signal's existing trace data.

  Returns `:ok` if trace data was found and stored, `{:error, :no_trace}` otherwise.
  """
  @spec set_from_signal(Signal.t()) :: :ok | {:error, :no_trace}
  def set_from_signal(%Signal{} = signal) do
    case Trace.get(signal) do
      nil ->
        {:error, :no_trace}

      trace ->
        Process.put(@context_key, trace)
        replace_open_telemetry_context(trace)
        :ok
    end
  end

  @doc """
  Clears the trace context from the process dictionary.
  """
  @spec clear() :: :ok
  def clear do
    Process.delete(@context_key)
    restore_open_telemetry_context()
    :ok
  end

  @doc """
  Gets the current trace context, or nil if not set.
  """
  @spec get() :: map() | nil
  def get do
    Process.get(@context_key)
  end

  @doc false
  @spec capture() :: Captured.t()
  def capture do
    %Captured{trace: get(), otel_context: OpenTelemetry.current_context()}
  end

  @doc false
  @spec with_context(map() | Captured.t() | nil, (-> result)) :: result when result: term()
  def with_context(%Captured{} = captured, fun) when is_function(fun, 0) do
    with_contexts(captured.trace, captured.otel_context, fun)
  end

  def with_context(context, fun)
      when (is_map(context) or is_nil(context)) and is_function(fun, 0) do
    with_contexts(context, OpenTelemetry.context_from_trace(context), fun)
  end

  defp with_contexts(context, otel_context, fun) do
    previous = get()

    if context, do: Process.put(@context_key, context), else: Process.delete(@context_key)

    try do
      OpenTelemetry.with_context(otel_context, fun)
    after
      if previous,
        do: Process.put(@context_key, previous),
        else: Process.delete(@context_key)
    end
  end

  @doc """
  Propagates trace context to a new signal.

  Creates a child span with:
  - Same trace_id as current context
  - New span_id for the child signal
  - parent_span_id set to current span_id
  - causation_id set to the provided causation_id (typically input_signal.id)

  Returns `{:ok, traced_signal}` on success.

  Returns `{:error, :no_trace_context}` when the process has no trace,
  `{:error, :invalid_trace_context}` when the stored trace is malformed, or
  `{:error, :invalid_args}` when the signal or causation ID is invalid.
  """
  @spec propagate_to(Signal.t(), String.t()) ::
          {:ok, Signal.t()}
          | {:error, :no_trace_context | :invalid_trace_context | :invalid_args}
  def propagate_to(%Signal{} = signal, causation_id) when is_binary(causation_id) do
    case get() do
      nil ->
        {:error, :no_trace_context}

      trace ->
        case Trace.child_of(trace, causation_id) do
          {:error, :invalid_trace_context} = error -> error
          child -> Trace.put(signal, OpenTelemetry.inject_trace_context(child))
        end
    end
  end

  def propagate_to(_signal, _causation_id) do
    {:error, :invalid_args}
  end

  @doc """
  Returns the current trace context as telemetry metadata.

  Returns an empty map if no context is set.
  Keys are prefixed with `jido_` for telemetry namespace.
  """
  @spec to_telemetry_metadata() :: map()
  def to_telemetry_metadata do
    case get() do
      nil ->
        %{}

      trace ->
        trace
        |> Trace.telemetry_context()
        |> Enum.map(fn {k, v} -> {:"jido_#{k}", v} end)
        |> Map.new()
    end
  end

  defp replace_open_telemetry_context(trace) do
    restore_open_telemetry_context()

    case OpenTelemetry.restore_trace_context(trace) do
      nil -> :ok
      restore_context -> Process.put(@otel_restore_key, restore_context)
    end

    :ok
  end

  defp restore_open_telemetry_context do
    @otel_restore_key
    |> Process.delete()
    |> OpenTelemetry.detach_trace_context()
  end
end
