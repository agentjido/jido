defmodule Jido.Agent.Directive.Stop do
  @moduledoc "Stops the Agent Server after the Agent state commit."

  @schema Zoi.struct(
            __MODULE__,
            %{reason: Zoi.any(description: "Stop reason") |> Zoi.default(:normal)},
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
