defmodule Jido.Plugin.Spec do
  @moduledoc """
  The normalized representation of a plugin attached to an agent.

  Contains all metadata needed to integrate a plugin with an agent,
  including actions, schema, configuration, and signal patterns.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(description: "Plugin module"),
              name: Zoi.string(description: "Plugin name"),
              state_key: Zoi.atom(description: "Key for plugin state in agent"),
              description: Zoi.string(description: "Plugin description") |> Zoi.optional(),
              category: Zoi.string(description: "Plugin category") |> Zoi.optional(),
              vsn: Zoi.string(description: "Plugin version") |> Zoi.optional(),
              schema: Zoi.any(description: "Plugin state schema") |> Zoi.optional(),
              config_schema: Zoi.any(description: "Plugin config schema") |> Zoi.optional(),
              config:
                Zoi.map(Zoi.atom(), Zoi.any(), description: "Plugin config") |> Zoi.default(%{}),
              signal_patterns:
                Zoi.list(Zoi.string(), description: "Signal patterns to match") |> Zoi.default([]),
              tags: Zoi.list(Zoi.string(), description: "Plugin tags") |> Zoi.default([]),
              actions: Zoi.list(Zoi.atom(), description: "Available actions") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end
