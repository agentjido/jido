defmodule Jido.Agent.Directive.EmitToChild do
  @moduledoc "Sends one Signal to a tracked child Agent."

  @schema Zoi.struct(
            __MODULE__,
            %{
              tag: Zoi.any(description: "Tracked child tag"),
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
