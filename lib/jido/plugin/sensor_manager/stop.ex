defmodule Jido.Plugin.SensorManager.Stop do
  @moduledoc "Removes one desired sensor process."

  @schema Zoi.struct(
            __MODULE__,
            %{tag: Zoi.any(description: "Stable sensor tag")},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
