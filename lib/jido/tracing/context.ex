defmodule Jido.Tracing.Context do
  @moduledoc false

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

  @doc false
  @spec begin_turn(Signal.t()) :: map()
  def begin_turn(%Signal{} = signal) do
    restore_open_telemetry_context()

    trace =
      case Trace.get(signal) do
        nil ->
          Trace.new_root()

        parent ->
          attach_open_telemetry_parent(parent)

          case Trace.child_of(parent, Map.get(parent, :causation_id)) do
            {:error, :invalid_trace_context} -> Trace.new_root()
            child -> child
          end
      end

    put(trace)
    trace
  end

  @doc false
  @spec put(map() | nil) :: :ok
  def put(nil) do
    Process.delete(@context_key)
    :ok
  end

  def put(trace) when is_map(trace) do
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
  @spec get() :: map() | nil
  def get, do: Process.get(@context_key)

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

  @doc false
  @spec propagate_to(Signal.t(), String.t()) ::
          {:ok, Signal.t()}
          | {:error, :no_trace_context | :invalid_trace_context | :invalid_args}
  def propagate_to(%Signal{} = signal, causation_id) when is_binary(causation_id) do
    case get() do
      nil -> {:error, :no_trace_context}
      trace -> Trace.put(signal, Map.put(trace, :causation_id, causation_id))
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
