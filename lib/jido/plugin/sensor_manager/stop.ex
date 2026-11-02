defmodule Jido.Plugin.SensorManager.Stop do
  alias Jido.Joi
  @moduledoc "Removes one desired sensor process."

  alias Jido.Plugin.SensorManager

  @schema Joi.struct(
            __MODULE__,
            %{tag: Joi.any(description: "Stable sensor tag")},
            coerce: true
          )

  @typedoc "A Directive that removes one managed sensor."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Joi.schema()
  def schema, do: @schema

  @doc "Validates one desired sensor removal."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Joi.parse(@schema, Map.from_struct(directive)),
         :ok <- SensorManager.validate_tag(directive.tag) do
      {:ok, directive}
    end
  end
end
