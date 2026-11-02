defmodule Jido.Plugin.Scheduler.Cancel do
  @moduledoc "Cancels one recurring Signal schedule."

  alias Jido.Plugin.Scheduler

  @schema Zoi.struct(
            __MODULE__,
            %{job_id: Zoi.any(description: "Agent-local job id")},
            coerce: true
          )

  @typedoc "A recurring schedule cancellation Directive."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring schedule cancellation."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- Scheduler.validate_job_id(directive.job_id) do
      {:ok, directive}
    end
  end
end
