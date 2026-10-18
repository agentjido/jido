defmodule Jido.AgentServer.Directive.AgentSend do
  @moduledoc "Sends one Signal to a tracked Agent activation."

  @schema Zoi.struct(
            __MODULE__,
            %{
              name: Zoi.any(description: "Agent name"),
              signal: Zoi.any(description: "Signal to send to the child")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
