defmodule Jido.Agent.Directive.Emit do
  @moduledoc "Dispatches one Signal after the Agent state commit."

  @schema Zoi.struct(
            __MODULE__,
            %{
              signal: Zoi.any(description: "Signal to dispatch"),
              dispatch:
                Zoi.any(description: "Optional Signal dispatch configuration") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
