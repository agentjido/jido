defmodule Jido.Plugin.SensorManager.Init do
  @moduledoc "Input for one supervised sensor process."

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent_server: Zoi.pid(description: "Owning Agent Server process"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              tag: Zoi.any(description: "Stable sensor tag"),
              module: Zoi.module(description: "Sensor module"),
              config: Zoi.map(description: "Portable sensor configuration") |> Zoi.default(%{}),
              jido: Zoi.atom(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Optional Agent partition") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for sensor initialization."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
