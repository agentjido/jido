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
end
