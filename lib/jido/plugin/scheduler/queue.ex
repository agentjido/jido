defmodule Jido.Plugin.Scheduler.Queue do
  @moduledoc false
  @schema Zoi.struct(
            __MODULE__,
            %{
              job_id: Zoi.any(),
              generation: Zoi.integer() |> Zoi.min(0) |> Zoi.max(2_147_483_647),
              scheduled_at:
                Zoi.string() |> Zoi.refine({Jido.Plugin.Scheduler.Occurrence, :validate_utc, []}),
              scope: Zoi.any()
            },
            coerce: true
          )
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema

  @doc "Validates one durable occurrence queue request."
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- Jido.Plugin.Scheduler.validate_durable_id(directive.job_id),
         :ok <- Jido.Plugin.Scheduler.validate_occurrence_scope(directive.scope) do
      {:ok, directive}
    end
  end
end
