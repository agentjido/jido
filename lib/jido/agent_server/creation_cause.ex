defmodule Jido.AgentServer.CreationCause do
  @moduledoc false

  alias Jido.Signal
  alias Jido.Tracing.Trace

  @schema Zoi.struct(
            __MODULE__,
            %{
              trace_id: Zoi.string() |> Zoi.max(256),
              span_id: Zoi.string() |> Zoi.max(256),
              signal_id: Zoi.string() |> Zoi.max(256),
              turn_id: Zoi.string() |> Zoi.max(256)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  def capture(context, %{active: %{telemetry_span: %{metadata: metadata}}}) do
    trace = Trace.get(context.signal) || metadata

    attrs = %{
      trace_id: trace[:trace_id],
      span_id: trace[:span_id],
      signal_id: context.signal.id,
      turn_id: context.turn_id
    }

    case Zoi.parse(@schema, attrs) do
      {:ok, cause} -> cause
      {:error, _} -> nil
    end
  end

  def capture(_context, _state), do: nil

  def metadata(nil), do: %{}

  def metadata(%__MODULE__{} = cause) do
    cause
    |> Trace.child_of(cause.signal_id)
    |> Map.put(:cause_turn_id, cause.turn_id)
  end

  def put(signal, nil), do: signal

  def put(signal, %__MODULE__{} = cause) do
    {:ok, signal} = Trace.put(signal, Trace.child_of(cause, cause.signal_id))
    {:ok, signal} = Signal.put_context(signal, "jidocauseturnid", cause.turn_id)
    signal
  end
end
