defmodule Jido.Plugin.Scheduler.Occurrence do
  @moduledoc """
  Identity for one logical recurring schedule occurrence.

  The ID covers the Jido instance, Agent ID and partition, job ID, explicit
  generation, and scheduled UTC instant. It excludes process, node, arrival
  time, and Signal ID. Repeating those coordinates produces the same ID.

  Signals carry flat CloudEvents context attributes. Read them with
  `Jido.Plugin.Scheduler.occurrence/1`. Identity does not provide saved pending
  work, acknowledgement, or automatic redelivery.
  """
  alias Jido.Signal

  @attributes ["jidooccurrenceid", "jidoschedulegen", "jidoscheduledat"]
  @reserved @attributes ++ ["jidodurabletick"]
  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string() |> Zoi.min(1),
              generation: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647),
              scheduled_at: Zoi.string() |> Zoi.refine({__MODULE__, :validate_utc, []})
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the occurrence metadata schema."
  def schema, do: @schema

  @doc false
  def validate_utc(value, _opts) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, 0} -> :ok
      _ -> {:error, "scheduled_at must be a UTC timestamp"}
    end
  end

  @doc false
  def validate_template(signal) do
    if Enum.any?(@reserved, &(Signal.get_context(signal, &1) != nil)),
      do: {:error, :reserved_occurrence_metadata},
      else: :ok
  end

  @doc false
  def attach(signal, scope, job_id, generation, %DateTime{} = scheduled_at) do
    instant = DateTime.to_unix(scheduled_at, :microsecond)
    coordinates = {:jido_schedule_occurrence, 1, scope, job_id, generation, instant}
    bytes = :erlang.term_to_binary(coordinates, [:deterministic, {:minor_version, 2}])
    id = "occ_" <> Base.url_encode64(:crypto.hash(:sha256, bytes), padding: false)
    utc = instant |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()

    with {:ok, signal} <- Signal.put_context(signal, "jidooccurrenceid", id),
         {:ok, signal} <- Signal.put_context(signal, "jidoschedulegen", generation),
         {:ok, signal} <- Signal.put_context(signal, "jidoscheduledat", utc) do
      {:ok, signal}
    end
  end

  @doc "Reads validated occurrence metadata from a Signal."
  @spec from_signal(Signal.t()) :: {:ok, t()} | {:error, term()}
  def from_signal(%Signal{} = signal) do
    case Enum.map(@attributes, &Signal.get_context(signal, &1)) do
      [nil, nil, nil] ->
        {:error, :not_found}

      [id, generation, scheduled_at] ->
        Zoi.parse(@schema, %{id: id, generation: generation, scheduled_at: scheduled_at})
    end
  end
end
