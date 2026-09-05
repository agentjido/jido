defmodule Jido.Plugin.Dispatch.Send do
  @moduledoc "A post-commit Signal delivery request."

  @schema Zoi.struct(
            __MODULE__,
            %{
              signal: Zoi.struct(Jido.Signal, description: "Signal to deliver"),
              target: Zoi.any(description: "Jido Signal Dispatch target or target list")
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
