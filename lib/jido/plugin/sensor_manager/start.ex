defmodule Jido.Plugin.SensorManager.Start do
  alias Jido.Joi
  @moduledoc "Declares one desired sensor process."

  alias Jido.Plugin.SensorManager

  @schema Joi.struct(
            __MODULE__,
            %{
              tag: Joi.any(description: "Stable sensor tag"),
              sensor: Joi.module(description: "Sensor OTP module"),
              config: Joi.map(description: "Portable sensor configuration") |> Joi.default(%{})
            },
            coerce: true
          )

  @typedoc "A Directive that adds or replaces one managed sensor."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Validates one portable desired sensor declaration."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Joi.parse(@schema, Map.from_struct(directive)),
         :ok <- SensorManager.validate_tag(directive.tag),
         :ok <- SensorManager.validate_sensor(directive.sensor) do
      case Jido.Codec.Term.validate(directive.config, :config) do
        :ok ->
          {:ok, directive}

        {:error, path} ->
          SensorManager.invalid("Sensor config must contain portable data", %{
            path: path
          })
      end
    end
  end
end
