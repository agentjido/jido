defmodule Jido.Signal.Context do
  @moduledoc """
  Validates CloudEvents extension context attributes.

  Extension attributes are flat transport metadata. Domain data belongs in the
  Signal `data` field and can be validated by a custom Signal module.
  """

  alias Jido.Signal
  alias Jido.Trace

  @core_names ~w[
    specversion id source type subject time
    datacontenttype dataschema data data_base64
  ]
  @name_pattern ~r/\A[a-z][a-z0-9]{0,19}\z/
  @min_integer -2_147_483_648
  @max_integer 2_147_483_647
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
  def normalize(attributes) when is_map(attributes) do
    Enum.reduce_while(Map.to_list(attributes), {:ok, %{}}, fn {name, value}, {:ok, acc} ->
      with {:ok, name} <- normalize_name(name),
           :ok <- validate_value(value) do
        if Map.has_key?(acc, name) do
          {:halt, {:error, "duplicate extension attribute #{inspect(name)}"}}
        else
          {:cont, {:ok, Map.put(acc, name, value)}}
        end
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def normalize(_attributes), do: {:error, "extensions must be a map"}

  @doc "Adds one validated context attribute to a Signal."
  @spec put(Signal.t(), atom() | String.t(), value()) ::
          {:ok, Signal.t()} | {:error, String.t()}
  def put(%Signal{} = signal, name, value) do
    with {:ok, name} <- normalize_name(name),
         :ok <- validate_value(value) do
      {:ok, %{signal | extensions: Map.put(signal.extensions, name, value)}}
    end
  end

  def put(_signal, _name, _value), do: {:error, "expected a Signal struct"}

  @doc "Gets one context attribute from a Signal."
  @spec get(Signal.t(), atom() | String.t()) :: value() | nil
  def get(%Signal{} = signal, name) when is_atom(name) or is_binary(name) do
    Map.get(signal.extensions, to_string(name))
  end

  def get(_signal, _name), do: nil

  @doc "Deletes one context attribute from a Signal."
  @spec delete(Signal.t(), atom() | String.t()) :: Signal.t()
  def delete(%Signal{} = signal, name) when is_atom(name) or is_binary(name) do
    %{signal | extensions: Map.delete(signal.extensions, to_string(name))}
  end

  def delete(signal, _name), do: signal

  @doc "Lists the context attribute names on a Signal."
  @spec names(Signal.t()) :: [name()]
  def names(%Signal{} = signal), do: Map.keys(signal.extensions)
  def names(_signal), do: []

  @doc false
  @spec normalize_name(term()) :: {:ok, name()} | {:error, String.t()}
  def normalize_name(name) when is_atom(name), do: normalize_name(Atom.to_string(name))

  def normalize_name(name) when is_binary(name) do
    cond do
      name in @core_names ->
        {:error, "extension name #{inspect(name)} conflicts with a CloudEvents attribute"}

      Regex.match?(@name_pattern, name) ->
        {:ok, name}

      true ->
        {:error,
         "extension name #{inspect(name)} must start with a lower-case letter, contain only lower-case letters and digits, and have at most 20 characters"}
    end
  end

  def normalize_name(name), do: {:error, "invalid extension name #{inspect(name)}"}

  defp put_new_trace(signal, trace) do
    case put_trace(signal, trace) do
      {:ok, traced} -> {:ok, traced, trace}
      {:error, :invalid_trace_context} = error -> error
    end
  end

  defp put_trace_causation(trace, causation_id) when is_binary(causation_id),
    do: Trace.with_causation(trace, causation_id)

  defp put_trace_causation(trace, _causation_id), do: trace

  defp validate_value(value) when is_boolean(value), do: :ok

  defp validate_value(value)
       when is_integer(value) and value >= @min_integer and value <= @max_integer,
       do: :ok

  defp validate_value(value) when is_binary(value), do: :ok

  defp validate_value(value) do
    {:error,
     "extension values must be a Boolean, signed 32-bit Integer, String, Binary, URI, URI-reference, or Timestamp; got: #{inspect(value)}"}
  end
end
