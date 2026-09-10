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
    SpawnChild,
    SpawnProcess,
    Stop,
    StopChild
  }

  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext

  @type t ::
          AdoptChild.t()
          | Emit.t()
          | EmitToChild.t()
          | EmitToParent.t()
          | Error.t()
          | SpawnChild.t()
          | SpawnProcess.t()
          | Stop.t()
          | StopChild.t()

  @built_ins [
    AdoptChild,
    Emit,
    EmitToChild,
    EmitToParent,
    Error,
    SpawnChild,
    SpawnProcess,
    Stop,
    StopChild
  ]

  @restart_policies [:permanent, :temporary, :transient]
  @unsupported_spawn_child_opts [
    :node,
    :lifecycle_mod,
    :pool,
    :pool_key,
    :idle_timeout,
    :persistence,
    :restore,
    :state_version
  ]

  @doc "Returns true when the value is a built-in Agent Directive."
  @spec built_in?(term()) :: boolean()
  def built_in?(%{__struct__: module}), do: module in @built_ins
  def built_in?(_value), do: false

  @doc false
  @spec built_in_module?(module()) :: boolean()
  def built_in_module?(module) when is_atom(module), do: module in @built_ins

  @doc "Validates one built-in Agent Directive."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%{__struct__: module, signal: %Signal{} = signal} = directive)
      when module in [Emit, EmitToParent, EmitToChild] do
    with {:ok, signal} <- Zoi.parse(Signal.schema(), signal),
         {:ok, extensions} <- SignalContext.normalize(signal.extensions) do
      directive
      |> Map.from_struct()
      |> Map.put(:signal, %{signal | extensions: extensions})
      |> then(&Zoi.parse(module.schema(), &1))
    end
  end

  def validate(%{__struct__: module} = directive)
      when module in [Emit, EmitToParent, EmitToChild] do
    {:error,
     Jido.Error.validation_error("Agent Signal Directive requires a Jido.Signal",
       details: %{directive: directive}
     )}
  end

  def validate(%SpawnChild{} = directive) do
    with {:ok, directive} <- Zoi.parse(SpawnChild.schema(), Map.from_struct(directive)),
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
  def validate_spawn_child_opts(opts, _refinement_opts \\ [])

  def validate_spawn_child_opts(opts, _refinement_opts) when is_map(opts) do
    unsupported = Enum.filter(@unsupported_spawn_child_opts, &Map.has_key?(opts, &1))

    case unsupported do
      [] -> :ok
      [:node] -> {:error, "Use SpawnChild.node for placement, not opts.node"}
      keys -> {:error, "SpawnChild does not support lifecycle options #{inspect(keys)}"}
    end
  end

  def validate_spawn_child_opts(value, _refinement_opts),
    do: {:error, "SpawnChild opts must be a map, got: #{inspect(value)}"}

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
  @spec emit(Signal.t(), term()) :: Emit.t()
  def emit(signal, dispatch \\ nil), do: %Emit{signal: signal, dispatch: dispatch}

  @doc "Creates an Emit Directive for one target PID."
  @spec emit_to_pid(Signal.t(), pid(), keyword()) :: Emit.t()
  def emit_to_pid(signal, pid, opts \\ []) when is_pid(pid) and is_list(opts) do
    %Emit{signal: signal, dispatch: {:pid, Keyword.put(opts, :target, pid)}}
  end

  @doc "Creates an EmitToParent Directive."
  @spec emit_to_parent(Signal.t()) :: EmitToParent.t()
  def emit_to_parent(signal), do: %EmitToParent{signal: signal}

  @doc "Creates an EmitToChild Directive."
  @spec emit_to_child(term(), Signal.t()) :: EmitToChild.t()
  def emit_to_child(tag, signal), do: %EmitToChild{tag: tag, signal: signal}

  @doc "Creates an Error Directive."
  @spec error(term(), atom() | nil) :: Error.t()
  def error(error, context \\ nil), do: %Error{error: error, context: context}

  @doc "Creates a SpawnProcess Directive for an untracked supervised OTP process."
  @spec spawn_process(Supervisor.child_spec()) :: SpawnProcess.t()
  def spawn_process(child_spec), do: %SpawnProcess{child_spec: child_spec}

  @doc "Creates a SpawnChild Directive. Pass `node: target_node` for remote placement."
  @spec spawn_child(module() | Jido.Agent.t(), term(), keyword()) :: SpawnChild.t()
  def spawn_child(agent, tag, opts \\ []) do
    %SpawnChild{
      agent: agent,
      tag: tag,
      node: Keyword.get(opts, :node),
      opts: opts |> Keyword.get(:opts, %{}) |> Map.new(),
      meta: opts |> Keyword.get(:meta, %{}) |> Map.new(),
      restart: Keyword.get(opts, :restart, :transient)
    }
  end

  @doc "Creates an AdoptChild Directive."
  @spec adopt_child(pid() | String.t(), term(), map()) :: AdoptChild.t()
  def adopt_child(child, tag, meta \\ %{}), do: %AdoptChild{child: child, tag: tag, meta: meta}

  @doc "Creates a StopChild Directive."
  @spec stop_child(term(), term()) :: StopChild.t()
  def stop_child(tag, reason \\ :normal), do: %StopChild{tag: tag, reason: reason}

  @doc "Creates a Stop Directive."
  @spec stop(term()) :: Stop.t()
  def stop(reason \\ :normal), do: %Stop{reason: reason}
end
