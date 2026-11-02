defmodule Jido.Plugin.SensorManager.Stop do
  @moduledoc "Removes one desired sensor process."

  alias Jido.Plugin.SensorManager

  @schema Zoi.struct(
            __MODULE__,
            %{tag: Zoi.any(description: "Stable sensor tag")},
            coerce: true
          )

  @typedoc "A Directive that removes one managed sensor."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Validates one desired sensor removal."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         :ok <- SensorManager.validate_tag(directive.tag) do
      {:ok, directive}
    end
  end
end
