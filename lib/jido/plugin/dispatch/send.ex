defmodule Jido.Plugin.Dispatch.Send do
  @moduledoc "A post-commit Signal delivery request."

  @schema Zoi.struct(
            __MODULE__,
            %{
              signal: Jido.Signal.schema(),
              target: Zoi.any(description: "Jido Signal Dispatch target or target list")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Validates one delivery request and its dispatch target."
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Zoi.parse(@schema, Map.from_struct(directive)),
         {:ok, target} <- Jido.Signal.Dispatch.validate_opts(directive.target) do
      {:ok, %{directive | target: target}}
    end
  end
end
