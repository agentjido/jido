defmodule Jido.Plugin.SensorManager.Start do
  alias Jido.Joi
  @moduledoc "Declares one desired sensor process."

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
         :ok <- validate_tag(directive.tag),
         :ok <- validate_sensor(directive.sensor) do
      case Jido.Codec.Term.validate(directive.config, :config) do
        :ok ->
          {:ok, directive}

        {:error, path} ->
          invalid("Sensor config must contain portable data", %{
            path: path
          })
      end
    end
  end

  @doc false
  def validate_tag(nil), do: invalid("Sensor tag must not be nil", %{tag: nil})

  def validate_tag(tag) do
    case Jido.Codec.Term.validate(tag, :tag) do
      :ok -> :ok
      {:error, path} -> invalid("Sensor tag must contain portable data", %{path: path})
    end
  end

  defp validate_sensor(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :child_spec, 1) do
      :ok
    else
      _invalid -> invalid("Sensor must define child_spec/1", %{sensor: module})
    end
  end

  defp invalid(message, details) do
    {:error, Jido.Error.validation_error(message, kind: :config, details: details)}
  end
end
