defmodule Jido.Agent.Directive.AdoptChild do
  @moduledoc "Attaches one live orphaned or unattached child Agent."

  @schema Zoi.struct(
            __MODULE__,
            %{
              child: Zoi.any(description: "Child PID or Agent id"),
              tag: Zoi.any(description: "Child relationship tag"),
              meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
