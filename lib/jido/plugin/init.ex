defmodule Jido.Plugin.Init do
  @moduledoc """
  Input for one supervised Agent Plugin runtime generation.

  `plugin_state` is the portable value selected from this Plugin's owned field
  in the complete Agent state map. It is a runtime bootstrap view, not a second
  stored state map. It is paired with `state_version` when the Agent Server
  builds the value. A replacement runtime gets a new Init value from the latest
  complete commit. Runtime handles and the complete Agent are not part of this
  value.

  Use `Jido.Plugin.state/2` when a running resource must read state after a
  later commit.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent_server: Zoi.pid(description: "Owning Agent Server process"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              module: Zoi.module(description: "Plugin module"),
              plugin_state:
                Zoi.any(description: "Immutable value of the Plugin-owned Agent field")
                |> Zoi.optional(),
              state_version:
                Zoi.integer(description: "Agent state version paired with the owned value")
                |> Zoi.min(0)
                |> Zoi.default(0),
              jido: Zoi.atom(description: "Optional Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Optional Agent partition") |> Zoi.optional(),
              options: Zoi.keyword(Zoi.any(), description: "Plugin options") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the data schema for Plugin runtime initialization."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema
end
