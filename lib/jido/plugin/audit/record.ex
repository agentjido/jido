defmodule Jido.Plugin.Audit.Record do
  @moduledoc "One portable domain audit record."

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Stable audit record identifier"),
              at: Zoi.integer(description: "Record time in Unix milliseconds") |> Zoi.min(0),
              event: Zoi.any(description: "Domain event"),
              outcome: Zoi.atom(description: "Domain outcome"),
              metadata: Zoi.map(description: "Portable record metadata") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
