defmodule Jido.Signal.Context do
  @moduledoc """
  Validates CloudEvents extension context attributes.

  Extension attributes are flat transport metadata. Domain data belongs in the
  Signal `data` field and can be validated by a custom Signal module.
  """

  alias Jido.Signal
  alias Jido.Trace

  @traceparent "traceparent"
  @tracestate "tracestate"
  @causation "jidocausationid"
  @legacy_trace_names ~w(jidotraceid jidospanid jidoparentspanid)

  @type name :: String.t()
  @type int32 :: -2_147_483_648..2_147_483_647
  @type value :: boolean() | int32() | binary()
  @type t :: %{optional(name()) => value()}

  @doc "Gets the valid Trace carried by a Signal."
  @spec get_trace(Signal.t()) :: Trace.t() | nil
  def get_trace(%Signal{} = signal) do
    case get(signal, @traceparent) do
      traceparent when is_binary(traceparent) ->
        case Trace.from_traceparent(traceparent, get(signal, @tracestate)) do
          {:ok, trace} -> put_trace_causation(trace, get(signal, @causation))
          {:error, :invalid_traceparent} -> nil
        end

      _missing ->
        nil
    end
  end

  def get_trace(_signal), do: nil

  @doc "Puts a valid Trace on a Signal."
  @spec put_trace(Signal.t(), Trace.t()) ::
          {:ok, Signal.t()} | {:error, :invalid_trace_context | :invalid_args}
  def put_trace(%Signal{} = signal, %Trace{} = trace) do
    if Trace.valid?(trace) do
      attributes =
        %{
          @traceparent => Trace.to_traceparent(trace),
          @tracestate => trace.tracestate,
          @causation => trace.causation_id
        }
        |> Map.reject(fn {_name, value} -> is_nil(value) end)

      signal = delete_trace(signal)
      {:ok, %{signal | extensions: Map.merge(signal.extensions, attributes)}}
    else
      {:error, :invalid_trace_context}
    end
  end

  def put_trace(_signal, _trace), do: {:error, :invalid_args}

  @doc "Deletes W3C, causation, and legacy trace attributes from a Signal."
  @spec delete_trace(Signal.t()) :: Signal.t()
  def delete_trace(%Signal{} = signal) do
    Enum.reduce(
      [@traceparent, @tracestate, @causation | @legacy_trace_names],
      signal,
      &delete(&2, &1)
    )
  end

  def delete_trace(signal), do: signal

  @doc "Returns the Signal trace, or creates and stores a new root Trace."
  @spec ensure_trace(Signal.t(), keyword()) ::
          {:ok, Signal.t(), Trace.t()} | {:error, :invalid_trace_context}
  def ensure_trace(%Signal{} = signal, opts \\ []) do
    case get_trace(signal) do
      %Trace{} = trace -> {:ok, signal, trace}
      nil -> put_new_trace(signal, Trace.new(opts))
    end
  end

  @doc "Lists the Signal extension names used for Trace propagation."
  @spec trace_names() :: [String.t()]
  def trace_names, do: [@traceparent, @tracestate, @causation]

  @doc "Validates and normalizes a context attribute map."
  @spec normalize(map()) :: {:ok, t()} | {:error, String.t()}
  def normalize(attributes), do: Signal.normalize_extensions(attributes)

  @doc "Adds one validated context attribute to a Signal."
  @spec put(Signal.t(), atom() | String.t(), value()) ::
          {:ok, Signal.t()} | {:error, String.t()}
  def put(signal, name, value), do: Signal.put_context(signal, name, value)

  @doc "Gets one context attribute from a Signal."
  @spec get(Signal.t(), atom() | String.t()) :: value() | nil
  def get(signal, name), do: Signal.get_context(signal, name)

  @doc "Deletes one context attribute from a Signal."
  @spec delete(Signal.t(), atom() | String.t()) :: Signal.t()
  def delete(signal, name), do: Signal.delete_context(signal, name)

  @doc "Lists the context attribute names on a Signal."
  @spec names(Signal.t()) :: [name()]
  def names(signal), do: Signal.list_context(signal)

  @doc false
  @spec normalize_name(term()) :: {:ok, name()} | {:error, String.t()}
  def normalize_name(name), do: Signal.normalize_extension_name(name)

  defp put_new_trace(signal, trace) do
    case put_trace(signal, trace) do
      {:ok, traced} -> {:ok, traced, trace}
      {:error, :invalid_trace_context} = error -> error
    end
  end

  defp put_trace_causation(trace, causation_id) when is_binary(causation_id),
    do: Trace.with_causation(trace, causation_id)

  defp put_trace_causation(trace, _causation_id), do: trace
end
