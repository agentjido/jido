defmodule Jido.Agent.Directive.SpawnAgent do
  @moduledoc """
  Starts and tracks one logical child Agent on the selected Erlang node.

  Omit `node` to use the parent's node. A remote node must run the same named
  Jido instance and have the Agent module available. Remote startup uses the
  parent's `directive_timeout`. A lost reply is an indeterminate outcome;
  retrying the same request resolves the same child identity.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Agent module or Agent value"),
              tag: Zoi.any(description: "Child relationship tag"),
              node:
                Zoi.atom(description: "Target Erlang node; nil selects the local node")
                |> Zoi.optional(),
              opts:
                Zoi.map(description: "Child Agent Server options")
                |> Zoi.refine({Jido.Agent.Directive, :validate_spawn_agent_opts, []})
                |> Zoi.default(%{}),
              meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{}),
              restart:
                Zoi.atom(description: "OTP restart policy")
                |> Zoi.refine({Jido.Agent.Directive, :validate_restart_policy, []})
                |> Zoi.default(:transient)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
