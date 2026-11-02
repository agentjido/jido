defmodule Jido.Persistence.Plugin.Context do
  alias Jido.Joi
  @moduledoc "Bounded format context for one Plugin-owned state conversion."

  alias Jido.Error

  @schema Joi.struct(
            __MODULE__,
            %{
              plugin: Joi.module(description: "Plugin package module"),
              plugin_vsn: Joi.integer(description: "Plugin package version") |> Joi.min(1),
              record_format: Joi.integer(description: "Persistence record format version") |> Joi.min(1),
              direction: Joi.enum([:dump, :load]),
              reason: Joi.any(description: "Persistence operation reason")
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for a Persistence Plugin context."
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Validates one Persistence Plugin context."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = context) do
    case Joi.parse(@schema, context) do
      {:ok, validated} -> {:ok, validated}
      {:error, issues} -> invalid("Persistence Plugin context is invalid", %{issues: issues})
    end
  end

  def validate(value),
    do: invalid("Expected a Jido.Persistence.Plugin.Context value", %{value: value})

  defp invalid(message, details) do
    {:error,
     Error.validation_error(message,
       kind: :input,
       subject: __MODULE__,
       details: details
     )}
  end
end
