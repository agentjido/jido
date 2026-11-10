defmodule Jido.Plugin.SensorManager.Init do
  alias Jido.Joi
  @moduledoc "Input for one supervised sensor process."

  @schema Joi.struct(
            __MODULE__,
            %{
              agent_server: Joi.pid(description: "Owning Agent Server process"),
              agent_id: Joi.string(description: "Owning Agent identifier"),
              tag: Joi.any(description: "Stable sensor tag"),
              module: Joi.module(description: "Sensor module"),
              config: Joi.map(description: "Portable sensor configuration") |> Joi.default(%{}),
              jido: Joi.atom(description: "Optional Jido instance") |> Joi.optional(),
              partition: Joi.any(description: "Optional Agent partition") |> Joi.optional()
            },
            coerce: true
          )

  @typedoc "Initialization data passed to one managed sensor."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc "Returns the data schema for sensor initialization."
  @spec schema() :: Joi.schema()
  def schema, do: @schema
end
