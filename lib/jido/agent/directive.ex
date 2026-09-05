defmodule Jido.Agent.Directive do
  @moduledoc """
  Runtime work returned by an Agent executable turn.

  A Directive does not change Agent domain state. The terminal Action or Flow
  output is the complete next Agent state. `Jido.AgentServer` commits that
  state before it interprets these Directives. A dispatch failure does not
  undo that commit. A later Agent state change must enter through a Signal.

  Directives request runtime operations or work that must happen after commit.
  An Action or Flow can also perform synchronous I/O before returning its
  complete state. That I/O is outside the Agent state transaction and is not
  undone if the Turn fails.
  """

  alias __MODULE__.{
    AdoptChild,
    Emit,
    EmitToChild,
    EmitToParent,
    Error,
    Spawn,
    SpawnAgent,
    Stop,
    StopChild
  }

  @type t ::
          AdoptChild.t()
          | Emit.t()
          | EmitToChild.t()
          | EmitToParent.t()
          | Error.t()
          | Spawn.t()
          | SpawnAgent.t()
          | Stop.t()
          | StopChild.t()

  @built_ins [
    AdoptChild,
    Emit,
    EmitToChild,
    EmitToParent,
    Error,
    Spawn,
    SpawnAgent,
    Stop,
    StopChild
  ]

  @restart_policies [:permanent, :temporary, :transient]
  @unsupported_spawn_agent_opts [
    :node,
    :lifecycle_mod,
    :pool,
    :pool_key,
    :idle_timeout,
    :persistence,
    :restore,
    :state_version
  ]

  defmodule Error do
    @moduledoc "Reports a structured turn or runtime error to the Server policy."

    @schema Zoi.struct(
              __MODULE__,
              %{
                error: Zoi.any(description: "Error value"),
                context: Zoi.atom(description: "Optional error context") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule Emit do
    @moduledoc "Dispatches one Signal after the Agent state commit."

    @schema Zoi.struct(
              __MODULE__,
              %{
                signal: Zoi.any(description: "Signal to dispatch"),
                dispatch:
                  Zoi.any(description: "Optional Signal dispatch configuration") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule EmitToParent do
    @moduledoc "Sends one Signal to the current logical parent Agent."

    @schema Zoi.struct(
              __MODULE__,
              %{signal: Zoi.any(description: "Signal to send to the parent")},
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule EmitToChild do
    @moduledoc "Sends one Signal to a tracked child Agent."

    @schema Zoi.struct(
              __MODULE__,
              %{
                tag: Zoi.any(description: "Tracked child tag"),
                signal: Zoi.any(description: "Signal to send to the child")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule Spawn do
    @moduledoc "Starts one generic process under the Jido instance supervisor."

    @schema Zoi.struct(
              __MODULE__,
              %{
                child_spec: Zoi.any(description: "OTP child specification"),
                tag: Zoi.any(description: "Optional correlation tag") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule SpawnAgent do
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

  defmodule AdoptChild do
    @moduledoc "Attaches one live orphaned or unattached child Agent."

    @schema Zoi.struct(
              __MODULE__,
              %{
                child: Zoi.any(description: "Child PID or Agent id"),
                tag: Zoi.any(description: "Child relationship tag"),
                meta: Zoi.map(description: "Relationship metadata") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule StopChild do
    @moduledoc "Stops and untracks one child Agent."

    @schema Zoi.struct(
              __MODULE__,
              %{
                tag: Zoi.any(description: "Tracked child tag"),
                reason: Zoi.any(description: "Stop reason") |> Zoi.default(:normal)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema
  end

  defmodule Stop do
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

  @doc "Returns true when the value is a built-in Agent Directive."
  @spec built_in?(term()) :: boolean()
  def built_in?(%{__struct__: module}), do: module in @built_ins
  def built_in?(_value), do: false

  @doc false
  @spec built_in_module?(module()) :: boolean()
  def built_in_module?(module) when is_atom(module), do: module in @built_ins

  @doc "Validates one built-in Agent Directive."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%Emit{signal: %Jido.Signal{}} = directive),
    do: Zoi.parse(Emit.schema(), Map.from_struct(directive))

  def validate(%EmitToParent{signal: %Jido.Signal{}} = directive),
    do: Zoi.parse(EmitToParent.schema(), Map.from_struct(directive))

  def validate(%EmitToChild{signal: %Jido.Signal{}} = directive),
    do: Zoi.parse(EmitToChild.schema(), Map.from_struct(directive))

  def validate(%{__struct__: module} = directive)
      when module in [Emit, EmitToParent, EmitToChild] do
    {:error,
     Jido.Error.validation_error("Agent Signal Directive requires a Jido.Signal",
       details: %{directive: directive}
     )}
  end

  def validate(%SpawnAgent{} = directive) do
    with {:ok, directive} <- Zoi.parse(SpawnAgent.schema(), Map.from_struct(directive)),
         :ok <- validate_agent_target(directive.agent) do
      {:ok, directive}
    end
  end

  def validate(%{__struct__: module} = directive) when module in @built_ins do
    Zoi.parse(module.schema(), Map.from_struct(directive))
  end

  def validate(value) do
    {:error,
     Jido.Error.validation_error("Unknown Agent Directive",
       details: %{directive: value}
     )}
  end

  @doc false
  def validate_restart_policy(restart, _opts \\ [])
  def validate_restart_policy(restart, _opts) when restart in @restart_policies, do: :ok

  def validate_restart_policy(restart, _opts) do
    {:error, "restart must be one of #{inspect(@restart_policies)}, got: #{inspect(restart)}"}
  end

  @doc false
  def validate_spawn_agent_opts(opts, _refinement_opts \\ [])

  def validate_spawn_agent_opts(opts, _refinement_opts) when is_map(opts) do
    unsupported = Enum.filter(@unsupported_spawn_agent_opts, &Map.has_key?(opts, &1))

    case unsupported do
      [] -> :ok
      [:node] -> {:error, "Use SpawnAgent.node for placement, not opts.node"}
      keys -> {:error, "SpawnAgent does not support lifecycle options #{inspect(keys)}"}
    end
  end

  def validate_spawn_agent_opts(value, _refinement_opts),
    do: {:error, "SpawnAgent opts must be a map, got: #{inspect(value)}"}

  @doc false
  def validate_agent_target(%Jido.Agent{} = agent) do
    case Jido.Agent.validate(agent) do
      {:ok, _agent} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  def validate_agent_target(module) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :new, 0) or function_exported?(module, :new, 1) do
      :ok
    else
      _reason -> {:error, {:invalid_agent_module, module}}
    end
  end

  def validate_agent_target(value), do: {:error, {:invalid_agent, value}}

  @doc "Creates an Emit Directive."
  def emit(signal, dispatch \\ nil), do: %Emit{signal: signal, dispatch: dispatch}

  @doc "Creates an Emit Directive for one target PID."
  def emit_to_pid(signal, pid, opts \\ []) when is_pid(pid) and is_list(opts) do
    %Emit{signal: signal, dispatch: {:pid, Keyword.put(opts, :target, pid)}}
  end

  @doc "Creates an EmitToParent Directive."
  def emit_to_parent(signal), do: %EmitToParent{signal: signal}

  @doc "Creates an EmitToChild Directive."
  def emit_to_child(tag, signal), do: %EmitToChild{tag: tag, signal: signal}

  @doc "Creates an Error Directive."
  def error(error, context \\ nil), do: %Error{error: error, context: context}

  @doc "Creates a generic Spawn Directive."
  def spawn(child_spec, tag \\ nil), do: %Spawn{child_spec: child_spec, tag: tag}

  @doc "Creates a SpawnAgent Directive. Pass `node: target_node` for a remote owned child."
  def spawn_agent(agent, tag, opts \\ []) do
    %SpawnAgent{
      agent: agent,
      tag: tag,
      node: Keyword.get(opts, :node),
      opts: opts |> Keyword.get(:opts, %{}) |> Map.new(),
      meta: opts |> Keyword.get(:meta, %{}) |> Map.new(),
      restart: Keyword.get(opts, :restart, :transient)
    }
  end

  @doc "Creates an AdoptChild Directive."
  def adopt_child(child, tag, meta \\ %{}), do: %AdoptChild{child: child, tag: tag, meta: meta}

  @doc "Creates a StopChild Directive."
  def stop_child(tag, reason \\ :normal), do: %StopChild{tag: tag, reason: reason}

  @doc "Creates a Stop Directive."
  def stop(reason \\ :normal), do: %Stop{reason: reason}
end
