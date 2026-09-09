defmodule Jido.Persistence.Plugin.Context do
  @moduledoc "Bounded format context for one Plugin-owned state conversion."

  alias Jido.Error

  @schema Zoi.struct(
            __MODULE__,
            %{
              plugin: Zoi.module(description: "Plugin package module"),
              plugin_vsn: Zoi.integer(description: "Plugin package version") |> Zoi.min(1),
              record_format:
                Zoi.integer(description: "Persistence record format version") |> Zoi.min(1),
              direction: Zoi.enum([:dump, :load]),
              reason: Zoi.any(description: "Persistence operation reason")
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the static schema for a Persistence Plugin context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates one Persistence Plugin context."
  @spec validate(term()) :: {:ok, t()} | {:error, Error.ValidationError.t()}
  def validate(%__MODULE__{} = context) do
    case Zoi.parse(@schema, context) do
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
