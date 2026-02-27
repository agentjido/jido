defmodule Jido.Observe.SpanCtx do
  @moduledoc """
  Span context for observability tracking.

  Contains all necessary information to finish a span that was started
  with `Jido.Observe.start_span/2`.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              event_prefix: Zoi.list(Zoi.atom(), description: "Telemetry event prefix"),
              start_time: Zoi.integer(description: "Monotonic start time in nanoseconds"),
              start_system_time: Zoi.integer(description: "System start time in nanoseconds"),
              metadata: Zoi.map(description: "Event metadata"),
              tracer_module:
                Zoi.atom(description: "Pinned tracer module for this span") |> Zoi.optional(),
              tracer_ctx: Zoi.any(description: "Tracer-specific context") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new SpanCtx from a map of attributes.

  Returns `{:ok, span_ctx}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  def new(_), do: {:error, Jido.Error.validation_error("SpanCtx requires a map")}

  @doc """
  Creates a new SpanCtx from a map, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, span_ctx} -> span_ctx
      {:error, reason} -> raise Jido.Error.validation_error("Invalid SpanCtx", details: reason)
    end
  end
end
