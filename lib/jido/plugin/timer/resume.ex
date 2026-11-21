defmodule Jido.Plugin.Timer.Resume do
  @moduledoc "Resumes one paused recurring interval."

  alias Jido.Joi
  alias Jido.Plugin.Timer.CronRules

  @schema Joi.struct(__MODULE__, %{job_id: Joi.any(description: "Agent-local job id")}, coerce: true)

  @typedoc "A recurring interval resume Directive."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring interval resume."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Jido.Agent.Directive.parse(@schema, Map.from_struct(directive)),
         :ok <- CronRules.to_error(CronRules.validate_job_id(directive.job_id)) do
      {:ok, directive}
    end
  end
end
