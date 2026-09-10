defmodule Jido.Agent.Directive.StopChild do
  @moduledoc "Stops and untracks one child Agent."

  @schema Zoi.struct(
            __MODULE__,
            %{
              tag: Zoi.any(description: "Tracked child tag"),
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
