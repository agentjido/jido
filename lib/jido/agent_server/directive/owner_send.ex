defmodule Jido.AgentServer.Directive.OwnerSend do
  @moduledoc "Sends one Signal to the owning Agent activation."

  @schema Zoi.struct(
            __MODULE__,
            %{signal: Zoi.any(description: "Signal to send to the parent")},
            coerce: true
          )

  @typedoc "A request to send one Signal to the owning Agent."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
