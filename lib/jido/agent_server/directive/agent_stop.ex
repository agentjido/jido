defmodule Jido.AgentServer.Directive.AgentStop do
  @moduledoc "Stops and untracks one Agent activation."

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.any(description: "Agent name"),
              reason: Zoi.any(description: "Stop reason") |> Zoi.default(:normal)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
