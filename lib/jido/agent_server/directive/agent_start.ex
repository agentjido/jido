defmodule Jido.AgentServer.Directive.AgentStart do
  @moduledoc """
  Starts and tracks one local Agent under its owner's OTP supervisor.

  `opts` accepts instance `id` and initial `state`, plus AgentServer options.
  A complete Agent instance supplies its own identity and state. Remote nodes
  are rejected before commit. `restart` selects the OTP restart policy.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Agent module or Agent value"),
              name: Zoi.any(description: "Agent name"),
              node:
                Zoi.atom(description: "Target Erlang node; nil selects the local node")
                |> Zoi.optional(),
              opts:
                Zoi.map(description: "AgentServer options")
                |> Zoi.refine({Jido.AgentServer.Directive, :validate_agent_start_opts, []})
                |> Zoi.default(%{}),
              meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{}),
              restart:
                Zoi.atom(description: "OTP restart policy")
                |> Zoi.refine({Jido.AgentServer.Directive, :validate_restart_policy, []})
                |> Zoi.default(:transient)
            },
            coerce: true
          )

  @typedoc "A request to start and track one local Agent."
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end
