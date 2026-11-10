defmodule Jido.Trace.Context do
  @moduledoc """
  Owns the process-local and OpenTelemetry context for a Jido Trace.
  """

  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext
  alias Jido.Telemetry.OpenTelemetry
  alias Jido.Trace

  @context_key {:jido, :trace_context}
  @otel_restore_key {:jido, :opentelemetry_restore_context}

  defmodule Captured do
    @moduledoc false

    @enforce_keys [:trace, :otel_context]
    defstruct [:trace, :otel_context]

    @type t :: %__MODULE__{trace: Trace.t() | nil, otel_context: term() | nil}
  end

  @doc false
  @spec begin_turn(Signal.t()) :: Trace.t()
  def begin_turn(%Signal{} = signal) do
    restore_open_telemetry_context()

    trace =
      case SignalContext.get_trace(signal) do
        nil ->
          Trace.new()

        %Trace{} = parent ->
          attach_open_telemetry_parent(parent)
          Trace.child(parent, causation_id: parent.causation_id)
      end

    put(trace)
    trace
  end

  @doc false
  @spec put(Trace.t() | nil) :: :ok
  def put(nil) do
    Process.delete(@context_key)
    :ok
  end

  def put(%Trace{} = trace) do
    Process.put(@context_key, trace)
    :ok
  end

  @doc false
  @spec clear() :: :ok
  def clear do
    Process.delete(@context_key)
    restore_open_telemetry_context()
    :ok
  end

  @doc false
  @spec get() :: Trace.t() | nil
  def get, do: Process.get(@context_key)

  @doc false
  @spec capture() :: Captured.t()
  def capture, do: %Captured{trace: get(), otel_context: OpenTelemetry.capture_context()}

  @doc false
  @spec with_context(Trace.t() | Captured.t() | nil, (-> result)) :: result when result: term()
  def with_context(%Captured{} = captured, fun) when is_function(fun, 0),
    do: with_contexts(captured.trace, captured.otel_context, fun)

  def with_context(context, fun)
      when (is_struct(context, Trace) or is_nil(context)) and is_function(fun, 0),
      do: with_contexts(context, OpenTelemetry.context_from_trace(context), fun)

  @doc false
  @spec propagate_to(Signal.t(), String.t()) ::
          {:ok, Signal.t()}
          | {:error, :no_trace_context | :invalid_trace_context | :invalid_args}
  def propagate_to(%Signal{} = signal, causation_id) when is_binary(causation_id) do
    case get() do
      nil -> {:error, :no_trace_context}
      %Trace{} = trace -> SignalContext.put_trace(signal, Trace.with_causation(trace, causation_id))
    end
  end

  def propagate_to(_signal, _causation_id), do: {:error, :invalid_args}

  defp with_contexts(context, otel_context, fun) do
    previous = get()
    put(context)

    try do
      OpenTelemetry.with_context(otel_context, fun)
    after
      put(previous)
    end
  end

  defp attach_open_telemetry_parent(trace) do
    Process.put(@otel_restore_key, OpenTelemetry.restore_trace_context(trace))
  end

  defp restore_open_telemetry_context do
    @otel_restore_key
    |> Process.delete()
    |> OpenTelemetry.detach_trace_context()
  end
end
