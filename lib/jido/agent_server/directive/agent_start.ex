defmodule Jido.AgentServer.Directive.AgentStart do
  use Jido.Agent.Directive, built_in: true
  alias Jido.Joi

  @restart_policies [:permanent, :temporary, :transient]
  @unsupported_opts [
    :agent,
    :input,
    :jido,
    :partition,
    :runner,
    :node,
    :lifecycle_mod,
    :pool,
    :pool_key,
    :idle_timeout,
    :persistence,
    :restore,
    :state_version
  ]

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
                |> Joi.refine({__MODULE__, :validate_options, []})
                |> Joi.default(%{}),
              meta: Joi.map(description: "Relationship metadata") |> Joi.default(%{}),
              restart:
                Joi.atom(description: "OTP restart policy")
                |> Joi.refine({__MODULE__, :validate_restart, []})
                |> Joi.default(:transient)
            },
            coerce: true
          )

  @typedoc "A request to start and track one local Agent."
  @type t :: unquote(Joi.type_spec(@schema))
  @enforce_keys Joi.enforce_keys(@schema)
  defstruct Joi.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @impl Jido.Agent.Directive
  def validate(%__MODULE__{} = directive) do
    with {:ok, directive} <- Joi.parse(@schema, Map.from_struct(directive)),
         :ok <- validate_target(directive.agent) do
      {:ok, directive}
    end
  end

  def validate(value), do: super(value)

  @doc false
  def validate_restart(restart, _opts \\ [])
  def validate_restart(restart, _opts) when restart in @restart_policies, do: :ok

  def validate_restart(restart, _opts) do
    {:error, "restart must be one of #{inspect(@restart_policies)}, got: #{inspect(restart)}"}
  end

  @doc false
  def validate_options(opts, _refinement_opts \\ [])

  def validate_options(opts, _refinement_opts) when is_map(opts) do
    unsupported = Enum.filter(@unsupported_opts, &Map.has_key?(opts, &1))

    case unsupported do
      [] -> :ok
      [:input] -> {:error, "AgentStart does not support initialization input"}
      [:node] -> {:error, "Use AgentStart.node for placement, not opts.node"}
      keys -> {:error, "AgentStart does not support lifecycle options #{inspect(keys)}"}
    end
  end

  def validate_options(value, _refinement_opts),
    do: {:error, "AgentStart opts must be a map, got: #{inspect(value)}"}

  @doc false
  def validate_target(%Jido.Agent{} = agent) do
    case Jido.Agent.validate(agent) do
      {:ok, _agent} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def validate_target(module) when is_atom(module) do
    with {:ok, _definition} <- Jido.Agent.Validation.resolve(module) do
      :ok
    else
      _reason -> {:error, {:invalid_agent_module, module}}
    end
  end

  def validate_target(value), do: {:error, {:invalid_agent, value}}
end
