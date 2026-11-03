defmodule Jido.AgentServer.Directive.AgentStart do
  use Jido.Agent.Directive, built_in: true
  alias Jido.Joi

  @moduledoc """
  Starts and tracks one local Agent under its owner's OTP supervisor.

  `opts` accepts instance `id` and initial `state`, plus AgentServer options. A
  complete Agent instance supplies its own identity and state. Remote nodes are
  rejected before commit. `restart` selects the OTP restart policy.
  """

  @schema Joi.struct(
            __MODULE__,
            %{
              agent: Joi.any(description: "Agent module or Agent value"),
              name: Joi.any(description: "Agent name"),
              node:
                Joi.atom(description: "Target Erlang node; nil selects the local node")
                |> Joi.optional(),
              opts:
                Joi.map(description: "AgentServer options")
                |> Joi.refine({Jido.AgentServer.Directive, :validate_agent_start_opts, []})
                |> Joi.default(%{}),
              meta: Joi.map(description: "Relationship metadata") |> Joi.default(%{}),
              restart:
                Joi.atom(description: "OTP restart policy")
                |> Joi.refine({Jido.AgentServer.Directive, :validate_restart_policy, []})
                |> Joi.default(:transient)
            },
            coerce: true
          )

  @typedoc "A request to start and track one local Agent."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.Struct.enforce_keys(@schema)
  defstruct Joi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Joi.parse(@schema, Map.from_struct(directive)),
         :ok <- Jido.AgentServer.Directive.validate_agent_target(directive.agent) do
      {:ok, directive}
    end
  end

  def validate(value), do: super(value)
end
