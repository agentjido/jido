defmodule Jido.Plugin.SensorManager.Start do
  @moduledoc "Declares one desired sensor process."

  @schema Zoi.struct(
            __MODULE__,
            %{
              tag: Zoi.any(description: "Stable sensor tag"),
              sensor: Zoi.module(description: "Sensor OTP module"),
              config: Zoi.map(description: "Portable sensor configuration") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one portable desired sensor declaration."
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- Jido.Plugin.SensorManager.validate_tag(directive.tag),
         :ok <- Jido.Plugin.SensorManager.validate_sensor(directive.sensor),
         :ok <- Jido.Action.validate_static_data(directive.config) do
      {:ok, directive}
    else
      {:error, reason} when is_binary(reason) ->
        Jido.Plugin.SensorManager.invalid("Sensor config must contain portable data", %{
          reason: reason
        })

      {:error, _reason} = error ->
        error
    end
  end
end
