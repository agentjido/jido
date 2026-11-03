defmodule Jido.Trace do
  @moduledoc """
  One validated W3C trace value for Jido.

  The value stores the current trace and span identifiers, trace flags, and
  optional tracestate. A child also records its parent span and the application
  causation identifier that led to the child.

  `Jido.Signal.Context` owns Signal attachment. `Jido.Trace.Context` owns
  process-local and OpenTelemetry context.
  """

  alias Jido.Joi

  @trace_id_bytes 16
  @span_id_bytes 8
  @traceparent_pattern ~r/\A00-([0-9a-f]{32})-([0-9a-f]{16})-([0-9a-f]{2})\z/
  @trace_id_pattern ~r/\A[0-9a-f]{32}\z/
  @span_id_pattern ~r/\A[0-9a-f]{16}\z/
  @zero_trace_id String.duplicate("0", 32)
  @zero_span_id String.duplicate("0", 16)
  @tracestate_whitespace ~r/\A[ \t]+|[ \t]+\z/

  @schema Joi.struct(
            __MODULE__,
            %{
              trace_id:
                Joi.string()
                |> Joi.refine({__MODULE__, :validate_trace_id, []}),
              span_id:
                Joi.string()
                |> Joi.refine({__MODULE__, :validate_span_id, []}),
              trace_flags:
                Joi.string()
                |> Joi.refine({__MODULE__, :validate_trace_flags, []}),
              tracestate:
                Joi.string()
                |> Joi.refine({__MODULE__, :validate_tracestate, []})
                |> Joi.nullable()
                |> Joi.optional(),
              parent_span_id:
                Joi.string()
                |> Joi.refine({__MODULE__, :validate_span_id, []})
                |> Joi.nullable()
                |> Joi.optional(),
              causation_id:
                Joi.string()
                |> Joi.nullable()
                |> Joi.optional()
            }
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc "Returns the Joi schema for a Trace value."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Creates a new root Trace."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    validate_options!(opts, [:trace_flags, :tracestate])

    build!(%__MODULE__{
      trace_id: generate_id(@trace_id_bytes),
      span_id: generate_id(@span_id_bytes),
      trace_flags: Keyword.get(opts, :trace_flags, "00"),
      tracestate: Keyword.get(opts, :tracestate)
    })
  end

  @doc "Creates a child Trace with a new span ID."
  @spec child(t(), keyword()) :: t()
  def child(%__MODULE__{} = parent, opts \\ []) do
    validate_options!(opts, [:causation_id])

    if valid?(parent) do
      build!(%__MODULE__{
        trace_id: parent.trace_id,
        span_id: generate_id(@span_id_bytes),
        trace_flags: parent.trace_flags,
        tracestate: parent.tracestate,
        parent_span_id: parent.span_id,
        causation_id: Keyword.get(opts, :causation_id)
      })
    else
      raise ArgumentError, "invalid parent Trace"
    end
  end

  @doc "Returns a Trace with one causation identifier."
  @spec with_causation(t(), String.t() | nil) :: t()
  def with_causation(%__MODULE__{} = trace, causation_id)
      when is_binary(causation_id) or is_nil(causation_id),
      do: build!(%{trace | causation_id: causation_id})

  @doc "Parses a W3C version 00 traceparent value."
  @spec from_traceparent(String.t(), String.t() | nil) ::
          {:ok, t()} | {:error, :invalid_traceparent}
  def from_traceparent(traceparent, tracestate \\ nil)

  def from_traceparent(traceparent, tracestate) when is_binary(traceparent) do
    with [_, trace_id, span_id, trace_flags] <- Regex.run(@traceparent_pattern, traceparent),
         {:ok, trace} <-
           parse(%__MODULE__{
             trace_id: trace_id,
             span_id: span_id,
             trace_flags: trace_flags,
             tracestate: normalize_tracestate(tracestate)
           }) do
      {:ok, trace}
    else
      _invalid -> {:error, :invalid_traceparent}
    end
  end

  def from_traceparent(_traceparent, _tracestate), do: {:error, :invalid_traceparent}

  @doc "Formats a Trace as a W3C version 00 traceparent value."
  @spec to_traceparent(t()) :: String.t()
  def to_traceparent(%__MODULE__{} = trace) do
    if valid?(trace),
      do: "00-#{trace.trace_id}-#{trace.span_id}-#{trace.trace_flags}",
      else: raise(ArgumentError, "invalid Trace")
  end

  @doc "Returns the trace fields used as semantic telemetry metadata."
  @spec telemetry_context(t()) :: map()
  def telemetry_context(%__MODULE__{} = trace) do
    trace
    |> Map.take([:trace_id, :span_id, :parent_span_id, :causation_id])
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  @doc "Returns the W3C carrier and semantic fields as one flat metadata map."
  @spec metadata(t()) :: map()
  def metadata(%__MODULE__{} = trace) do
    trace
    |> telemetry_context()
    |> Map.put(:traceparent, to_traceparent(trace))
    |> maybe_put(:tracestate, trace.tracestate)
  end

  @doc "Checks a Trace struct or traceparent string."
  @spec valid?(t() | String.t() | term()) :: boolean()
  def valid?(%__MODULE__{} = trace), do: match?({:ok, _trace}, parse(trace))

  def valid?(traceparent) when is_binary(traceparent),
    do: match?({:ok, _trace}, from_traceparent(traceparent))

  def valid?(_value), do: false

  @doc false
  def validate_trace_id(value, _opts),
    do: validate_id(value, @trace_id_pattern, @zero_trace_id, "trace ID")

  @doc false
  def validate_span_id(value, _opts),
    do: validate_id(value, @span_id_pattern, @zero_span_id, "span ID")

  @doc false
  def validate_trace_flags(value, _opts) do
    if is_binary(value) and Regex.match?(~r/\A[0-9a-f]{2}\z/, value),
      do: :ok,
      else: {:error, "trace flags must be two lower-case hexadecimal characters"}
  end

  @doc false
  def validate_tracestate(value, _opts) do
    with true <- is_binary(value) and String.valid?(value) and byte_size(value) <= 512,
         members <- String.split(value, ",", trim: false),
         {:ok, keys} <- validate_tracestate_members(members),
         true <- Enum.count_until(keys, 33) <= 32,
         true <- length(Enum.uniq(keys)) == length(keys) do
      :ok
    else
      _invalid ->
        {:error, "tracestate must contain at most 32 unique, valid W3C list-members and 512 bytes"}
    end
  end

  defp parse(trace), do: Joi.parse(@schema, trace)

  defp build!(trace) do
    case parse(trace) do
      {:ok, trace} -> trace
      {:error, errors} -> raise ArgumentError, Joi.prettify_errors(errors)
    end
  end

  defp validate_options!(opts, allowed) do
    if Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [],
      do: :ok,
      else: raise(ArgumentError, "unexpected Trace options")
  end

  defp normalize_tracestate(nil), do: nil

  defp normalize_tracestate(tracestate) do
    case validate_tracestate(tracestate, []) do
      :ok -> tracestate
      {:error, _reason} -> nil
    end
  end

  defp validate_id(value, pattern, zero, name) do
    if is_binary(value) and value != zero and Regex.match?(pattern, value),
      do: :ok,
      else: {:error, "#{name} must be #{byte_size(zero)} lower-case hexadecimal characters and not all zero"}
  end

  defp validate_tracestate_members(members) do
    Enum.reduce_while(members, {:ok, []}, fn member, {:ok, keys} ->
      member = Regex.replace(@tracestate_whitespace, member, "")

      case String.split(member, "=", parts: 2) do
        [""] ->
          {:cont, {:ok, keys}}

        [key, value] ->
          if valid_tracestate_key?(key) and valid_tracestate_value?(value),
            do: {:cont, {:ok, [key | keys]}},
            else: {:halt, :error}

        _invalid ->
          {:halt, :error}
      end
    end)
  end

  defp valid_tracestate_key?(key) do
    Regex.match?(~r/\A[a-z][a-z0-9_\-*\/]{0,255}\z/, key) or
      Regex.match?(~r/\A[a-z0-9][a-z0-9_\-*\/]{0,240}@[a-z][a-z0-9_\-*\/]{0,13}\z/, key)
  end

  defp valid_tracestate_value?(value) when byte_size(value) in 1..256 do
    valid_chars? =
      Enum.all?(:binary.bin_to_list(value), fn char ->
        char in 0x20..0x2B or char in 0x2D..0x3C or char in 0x3E..0x7E
      end)

    valid_chars? and :binary.last(value) != 0x20
  end

  defp valid_tracestate_value?(_value), do: false

  defp generate_id(bytes) do
    id = bytes |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    if String.trim(id, "0") == "", do: generate_id(bytes), else: id
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
