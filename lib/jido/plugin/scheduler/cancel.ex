defmodule Jido.Plugin.Scheduler.Cancel do
  @moduledoc "Cancels one recurring Signal schedule."

  @schema Zoi.struct(
            __MODULE__,
            %{job_id: Zoi.any(description: "Agent-local job id")},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one recurring schedule cancellation."
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- Jido.Plugin.Scheduler.validate_durable_id(directive.job_id) do
      {:ok, directive}
    end
  end
end
