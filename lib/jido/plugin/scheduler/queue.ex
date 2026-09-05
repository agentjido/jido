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
end
