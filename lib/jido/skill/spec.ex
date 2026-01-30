defmodule Jido.Skill.Spec do
  @moduledoc """
  The normalized representation of a skill attached to an agent.

  Contains all metadata needed to integrate a skill with an agent,
  including actions, schema, configuration, and signal patterns.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              module: Zoi.atom(description: "Skill module"),
              name: Zoi.string(description: "Skill name"),
              state_key: Zoi.atom(description: "Key for skill state in agent"),
              description: Zoi.string(description: "Skill description") |> Zoi.optional(),
              category: Zoi.string(description: "Skill category") |> Zoi.optional(),
              vsn: Zoi.string(description: "Skill version") |> Zoi.optional(),
              schema: Zoi.any(description: "Skill state schema") |> Zoi.optional(),
              config_schema: Zoi.any(description: "Skill config schema") |> Zoi.optional(),
              config:
                Zoi.map(Zoi.atom(), Zoi.any(), description: "Skill config") |> Zoi.default(%{}),
              signal_patterns:
                Zoi.list(Zoi.string(), description: "Signal patterns to match") |> Zoi.default([]),
              tags: Zoi.list(Zoi.string(), description: "Skill tags") |> Zoi.default([]),
              actions: Zoi.list(Zoi.atom(), description: "Available actions") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end
