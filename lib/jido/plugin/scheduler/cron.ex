defmodule Jido.Plugin.Scheduler.Cron do
  alias Jido.Joi
  @moduledoc "Creates or replaces one recurring Signal schedule."

  alias Jido.Plugin.Scheduler

  @schema Joi.struct(
            __MODULE__,
            %{
              job_id: Joi.any(description: "Agent-local job id"),
              cron: Joi.string(description: "Cron expression"),
              signal: Joi.struct(Jido.Signal, description: "Signal to send"),
              generation:
                Joi.integer(description: "Optional explicit generation for occurrence metadata")
                |> Joi.min(0)
                |> Joi.max(2_147_483_647)
                |> Joi.nullable()
                |> Joi.optional(),
              timezone:
                Joi.string(description: "Optional timezone")
                |> Joi.nullable()
                |> Joi.optional()
            },
            coerce: true
          )

  @typedoc "A recurring Signal Directive."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring schedule request."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Joi.parse(@schema, Map.from_struct(directive)),
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
