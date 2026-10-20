defmodule Jido.Plugin.Scheduler.Cron do
  @moduledoc "Creates or replaces one recurring Signal schedule."

  alias Jido.Plugin.Scheduler

  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id: Zoi.any(description: "Agent-local job id"),
              cron: Zoi.string(description: "Cron expression"),
              signal: Zoi.struct(Jido.Signal, description: "Signal to send"),
              generation:
                Zoi.integer(description: "Optional explicit generation for occurrence metadata")
                |> Zoi.min(0)
                |> Zoi.max(2_147_483_647)
                |> Zoi.nullable()
                |> Zoi.optional(),
              timezone:
                Zoi.string(description: "Optional timezone")
                |> Zoi.nullable()
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring schedule request."
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- Scheduler.validate_job_id(directive.job_id),
         {:ok, timezone} <-
           Scheduler.validate_cron_spec(
             directive.cron,
             directive.signal,
             directive.timezone
           ),
         :ok <- Scheduler.validate_occurrence(directive.signal, directive.generation) do
      {:ok, %{directive | timezone: timezone}}
    end
  end
end
