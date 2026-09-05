defmodule Jido.Plugin.Scheduler.Acknowledge do
  @moduledoc "Confirms a durable occurrence in the same commit as its business state."
  @schema Zoi.struct(__MODULE__, %{occurrence_id: Zoi.string() |> Zoi.min(1)}, coerce: true)
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  @doc false
  def schema, do: @schema
end
