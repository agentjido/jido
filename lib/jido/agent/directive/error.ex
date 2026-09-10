defmodule Jido.Agent.Directive.Error do
  @moduledoc "Reports a structured turn or runtime error to the Server policy."

  @schema Zoi.struct(
            __MODULE__,
            %{
              error: Zoi.any(description: "Error value"),
              context: Zoi.atom(description: "Optional error context") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
