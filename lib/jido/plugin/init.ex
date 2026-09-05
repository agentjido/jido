defmodule Jido.Plugin.Init do
  @moduledoc "Input for one supervised Agent Plugin runtime."

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent_server: Zoi.pid(description: "Owning Agent Server process"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              module: Zoi.module(description: "Plugin module"),
              jido: Zoi.atom(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Optional Agent partition") |> Zoi.optional(),
              options: Zoi.keyword(Zoi.any(), description: "Plugin options") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Plugin runtime initialization."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
