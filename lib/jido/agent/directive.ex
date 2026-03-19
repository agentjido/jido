defmodule Jido.Agent.Directive do
  @moduledoc """
  Typed directive structs for `Jido.Agent`.

  A *directive* is a pure description of an external effect for the runtime
  (e.g. `Jido.AgentServer`) to execute. Agents and strategies **never**
  interpret or execute directives; they only emit them.

  ## Signal Integration

  The Emit directive integrates with `Jido.Signal` and `Jido.Signal.Dispatch`:

  - `%Emit{}` - Dispatch a signal via configured adapters (pid, pubsub, bus, http, etc.)

  ## Design

  Directives are bare structs - no tuple wrappers. This enables:
  - Clean pattern matching on struct type
  - Protocol-based dispatch for extensibility
  - External packages can define custom directives

  ## Core Directives

    * `%Emit{}` - Dispatch a signal via `Jido.Signal.Dispatch`
    * `%Error{}` - Signal an error (wraps `Jido.Error.t()`)
    * `%Spawn{}` - Spawn a generic BEAM child process (fire-and-forget, no tracking)
    * `%SpawnAgent{}` - Spawn a child Jido agent with full hierarchy tracking
    * `%AdoptChild{}` - Attach an orphaned or unattached child to the current parent
    * `%StopChild{}` - Request a tracked child agent to stop gracefully
    * `%Schedule{}` - Schedule a delayed message
    * `%RunInstruction{}` - Execute an instruction at runtime and route result to `cmd/2`
    * `%Stop{}` - Stop the agent process (self)

  ## Usage

      alias Jido.Agent.Directive

      # Emit a signal (runtime will dispatch via configured adapters)
      %Directive.Emit{signal: my_signal}
      %Directive.Emit{signal: my_signal, dispatch: {:pubsub, topic: "events"}}
      %Directive.Emit{signal: my_signal, dispatch: {:pid, target: pid}}

      # Schedule for later
      %Directive.Schedule{delay_ms: 5000, message: :timeout}

      # Execute instruction at runtime
      %Directive.RunInstruction{instruction: instruction, result_action: :fsm_instruction_result}

  ## Extensibility

  External packages can define their own directive structs:

      defmodule MyApp.Directive.CallLLM do
        defstruct [:model, :prompt, :tag]
      end

  The runtime dispatches on struct type, so no changes to core are needed.
  """

  alias __MODULE__.{
    Emit,
    Error,
    Spawn,
    SpawnAgent,
    AdoptChild,
    StopChild,
    Schedule,
    RunInstruction,
    Stop,
    Cron,
    CronCancel
  }

  @typedoc """
  Any external directive struct (core or extension).

  This is intentionally `struct()` so external packages can define
  their own directive structs without modifying this type.
  """
  @type t :: struct()

  @typedoc "Built-in core directives."
  @type core ::
          Emit.t()
          | Error.t()
          | Spawn.t()
          | SpawnAgent.t()
          | AdoptChild.t()
          | StopChild.t()
          | Schedule.t()
          | RunInstruction.t()
          | Stop.t()
          | Cron.t()
          | CronCancel.t()

  @typedoc "Restart policy for spawned AgentServer children."
  @type restart_policy :: :permanent | :temporary | :transient

  @restart_policies [:permanent, :temporary, :transient]

  @doc false
  @spec valid_restart_policies() :: [restart_policy()]
  def valid_restart_policies, do: @restart_policies

  @doc false
  @spec validate_restart_policy(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_restart_policy(restart, _opts \\ [])

  def validate_restart_policy(restart, _opts) when restart in @restart_policies, do: :ok

  def validate_restart_policy(restart, _opts) do
    {:error, "restart must be one of #{inspect(@restart_policies)}, got: #{inspect(restart)}"}
  end

  # ============================================================================
  # Error - Signal an error from cmd/2
  # ============================================================================

  defmodule Error do
    @moduledoc """
    Signal an error from agent command processing.

    This directive carries a `Jido.Error.t()` for consistent error handling.
    The runtime can log, emit, or handle errors based on this directive.

    ## Fields

    - `error` - A `Jido.Error.t()` struct
    - `context` - Optional atom describing error context (e.g., `:normalize`, `:instruction`)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                error: Zoi.any(description: "Jido.Error struct"),
                context: Zoi.atom(description: "Error context") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Error."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Emit - Signal dispatch via Jido.Signal.Dispatch
  # ============================================================================

  defmodule Emit do
    @moduledoc """
    Dispatch a signal via `Jido.Signal.Dispatch`.

    The runtime interprets this directive by calling:

        Jido.Signal.Dispatch.dispatch(signal, dispatch_config)

    ## Fields

    - `signal` - A `Jido.Signal.t()` struct to dispatch
    - `dispatch` - Dispatch config: `{adapter, opts}` or list of configs
      - `:pid` - Direct to process
      - `:pubsub` - Via PubSub
      - `:bus` - To signal bus
      - `:http` / `:webhook` - HTTP endpoints
      - `:logger` / `:console` / `:noop` - Logging/testing

    If `dispatch` is omitted and the agent has no `default_dispatch`, runtime
    falls back to emitting to the current agent process (`self()`).

    ## Examples

        # Use agent's default dispatch (configured on AgentServer)
        %Emit{signal: signal}

        # Explicit dispatch to PubSub
        %Emit{signal: signal, dispatch: {:pubsub, topic: "events"}}

        # Multiple dispatch targets
        %Emit{signal: signal, dispatch: [
          {:pubsub, topic: "events"},
          {:logger, level: :info}
        ]}
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                signal: Zoi.any(description: "Jido.Signal.t() to dispatch"),
                dispatch:
                  Zoi.any(description: "Dispatch config: {adapter, opts} or list")
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Emit."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Spawn - Child process spawning
  # ============================================================================

  defmodule Spawn do
    @moduledoc """
    Spawn a generic BEAM child process under the agent's supervisor.

    This is a **low-level, fire-and-forget** directive for spawning non-agent
    processes (Tasks, GenServers, etc.). The spawned process is **not tracked**
    in the agent's children map and has no parent-child relationship semantics.

    Use `SpawnAgent` instead if you need to spawn another Jido agent with:
    - Parent-child hierarchy tracking
    - Process monitoring and exit signals
    - The ability to use `emit_to_parent/3` from the child
    - Lifecycle management via `StopChild`

    ## Fields

    - `child_spec` - Supervisor child_spec for the process to spawn
    - `tag` - Optional correlation tag for logging (not used for tracking)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                child_spec: Zoi.any(description: "Supervisor child_spec"),
                tag: Zoi.any(description: "Optional correlation tag") |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Spawn."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # SpawnAgent - Spawn a child agent with hierarchy tracking
  # ============================================================================

  defmodule SpawnAgent do
    @moduledoc """
    Spawn a child agent with parent-child hierarchy tracking.

    Unlike `Spawn`, this directive specifically spawns another Jido agent
    and sets up the logical parent-child relationship:

    - Child's parent reference points to the spawning agent
    - Parent monitors the child process
    - Parent tracks child in its children map by tag
    - Child exit signals are delivered to parent as `jido.agent.child.exit`
    - Child can use `emit_to_parent/3` while attached

    The logical relationship is independent from OTP supervisory ancestry. If
    the child later becomes orphaned, the current parent ref is cleared and the
    child must be explicitly reattached with `AdoptChild` before
    `emit_to_parent/3` works again.

    ## Fields

    - `agent` - Agent module (atom) or pre-built agent struct to spawn
    - `tag` - Tag for tracking this child (used as key in children map)
    - `opts` - Additional options passed to child AgentServer
    - `meta` - Metadata to pass to child via parent reference
    - `restart` - Restart policy for the child under supervision (default: `:transient`)

    ## Examples

        # Spawn a worker agent
        %SpawnAgent{agent: MyWorkerAgent, tag: :worker_1}

        # Spawn with custom ID and initial state
        %SpawnAgent{
          agent: MyWorkerAgent,
          tag: :processor,
          opts: %{id: "custom-id", initial_state: %{batch_size: 100}}
        }

        # Spawn with metadata for the child
        %SpawnAgent{
          agent: MyWorkerAgent,
          tag: :handler,
          meta: %{assigned_topic: "events.user"}
        }

        # Override restart behavior for long-lived workers
        %SpawnAgent{
          agent: MyWorkerAgent,
          tag: :supervised,
          restart: :permanent
        }
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                agent: Zoi.any(description: "Agent module (atom) or pre-built agent struct"),
                tag: Zoi.any(description: "Tag for tracking this child"),
                opts: Zoi.map(description: "Options for child AgentServer") |> Zoi.default(%{}),
                meta: Zoi.map(description: "Metadata to pass to child") |> Zoi.default(%{}),
                restart:
                  Zoi.atom(description: "Restart policy for the child")
                  |> Zoi.refine({Jido.Agent.Directive, :validate_restart_policy, []})
                  |> Zoi.default(:transient)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for SpawnAgent."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # AdoptChild - Attach an orphaned or unattached child agent
  # ============================================================================

  defmodule AdoptChild do
    @moduledoc """
    Attach an orphaned or unattached child agent to the current parent.

    This directive is the explicit reattachment path for Jido's logical
    hierarchy. It updates the live child runtime so the child can resume
    parent-directed communication with `emit_to_parent/3`.

    Adoption is explicit. Jido does not automatically reconnect children
    when a logical parent restarts.

    This updates the live runtime relationship only. It does not rewrite the
    child's original startup child spec, so a later child restart still uses
    the startup configuration that originally created the child.

    ## Fields

    - `child` - Child PID or child agent id to adopt
    - `tag` - Tag for tracking this adopted child
    - `meta` - Metadata to write into the child's new parent reference
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                child: Zoi.any(description: "Child PID or child id"),
                tag: Zoi.any(description: "Tag for tracking this adopted child"),
                meta:
                  Zoi.map(description: "Metadata to pass to the adopted child")
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for AdoptChild."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # StopChild - Stop a tracked child agent
  # ============================================================================

  defmodule StopChild do
    @moduledoc """
    Request that a tracked child agent stop gracefully.

    This directive provides symmetric lifecycle control for child agents
    spawned via `SpawnAgent`. It sends a shutdown signal to the child,
    allowing it to terminate cleanly.

    The child is identified by its `tag` (the key used in `SpawnAgent`).
    If the child is not found, the directive is a no-op.

    ## Fields

    - `tag` - Tag of the child to stop (must match a key in the children map)
    - `reason` - Reason for stopping (default: `:normal`)

    ## Examples

        # Stop a worker by tag
        %StopChild{tag: :worker_1}

        # Stop with a specific reason
        %StopChild{tag: :processor, reason: :shutdown}

    ## Behavior

    The runtime sends a `jido.agent.stop` signal to the child process,
    which triggers a graceful shutdown. The child's exit will be delivered
    back to the parent as a `jido.agent.child.exit` signal.

    `SpawnAgent` children default to `restart: :transient`, so a normal
    `StopChild` shutdown removes the child instead of immediately restarting it.
    Custom reasons are wrapped as `{:shutdown, reason}` so transient children
    are still removed cleanly.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                tag: Zoi.any(description: "Tag of the child to stop"),
                reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for StopChild."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Schedule - Delayed message scheduling
  # ============================================================================

  defmodule Schedule do
    @moduledoc """
    Schedule a delayed message to the agent.

    The runtime will send the message back to the agent after the delay.

    ## Fields

    - `delay_ms` - Delay in milliseconds (must be >= 0)
    - `message` - Message to send after delay
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                delay_ms: Zoi.integer(description: "Delay in milliseconds") |> Zoi.min(0),
                message: Zoi.any(description: "Message to send after delay")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Schedule."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # RunInstruction - Runtime instruction execution
  # ============================================================================

  defmodule RunInstruction do
    @moduledoc """
    Execute a `%Jido.Instruction{}` at runtime and route the result back to `cmd/2`.

    This directive lets strategies keep `cmd/2` pure by emitting instruction execution
    requests instead of calling `Jido.Exec.run/1` directly. The runtime executes the
    instruction, builds a result payload, then calls:

        agent_module.cmd(agent, {result_action, payload})

    ## Fields

    - `instruction` - The `%Jido.Instruction{}` to execute
    - `result_action` - Internal action atom/module for result handling in `cmd/2`
    - `meta` - Optional metadata echoed in the result payload
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                instruction: Zoi.any(description: "%Jido.Instruction{} to execute"),
                result_action:
                  Zoi.any(
                    description: "Action used when routing execution result back into cmd/2"
                  ),
                meta:
                  Zoi.map(Zoi.any(), Zoi.any(),
                    description: "Optional metadata for result payload"
                  )
                  |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for RunInstruction."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Stop - Stop the agent process
  # ============================================================================

  defmodule Stop do
    @moduledoc """
    Request that the agent process stop.

    ## Fields

    - `reason` - Reason for stopping (default: `:normal`)
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc "Returns the Zoi schema for Stop."
    @spec schema() :: Zoi.schema()
    def schema, do: @schema
  end

  # ============================================================================
  # Helper Constructors
  # ============================================================================

  @doc """
  Creates an Emit directive.

  If `dispatch` is omitted, runtime will use `AgentServer` `default_dispatch`.
  When no default is configured, runtime falls back to emitting to the current
  agent process (`self()`).

  ## Examples

      Directive.emit(signal)
      Directive.emit(signal, {:pubsub, topic: "events"})
  """
  @spec emit(term(), term()) :: Emit.t()
  def emit(signal, dispatch \\ nil) do
    %Emit{signal: signal, dispatch: dispatch}
  end

  @doc """
  Creates an Error directive.

  ## Examples

      Directive.error(Jido.Error.validation_error("Invalid input"))
      Directive.error(error, :normalize)
  """
  @spec error(term(), atom() | nil) :: Error.t()
  def error(error, context \\ nil) do
    %Error{error: error, context: context}
  end

  @doc """
  Creates a Spawn directive.

  ## Examples

      Directive.spawn({MyWorker, arg: value})
      Directive.spawn(child_spec, :worker_1)
  """
  @spec spawn(term(), term()) :: Spawn.t()
  def spawn(child_spec, tag \\ nil) do
    %Spawn{child_spec: child_spec, tag: tag}
  end

  @doc """
  Creates a SpawnAgent directive for spawning child agents with hierarchy tracking.

  ## Options

  - `:opts` - Additional options for the child AgentServer (map)
  - `:meta` - Metadata to pass to the child via parent reference (map)
  - `:restart` - Child restart policy under supervision (default: `:transient`)

  ## Examples

      Directive.spawn_agent(MyWorkerAgent, :worker_1)
      Directive.spawn_agent(MyWorkerAgent, :processor, opts: %{initial_state: %{batch_size: 100}})
      Directive.spawn_agent(MyWorkerAgent, :handler, meta: %{assigned_topic: "events"})
      Directive.spawn_agent(MyWorkerAgent, :durable, restart: :permanent)
  """
  @spec spawn_agent(term(), term(), keyword()) :: SpawnAgent.t()
  def spawn_agent(agent, tag, options \\ []) do
    opts = Keyword.get(options, :opts, %{})
    meta = Keyword.get(options, :meta, %{})
    restart = Keyword.get(options, :restart, :transient)

    case validate_restart_policy(restart) do
      :ok ->
        %SpawnAgent{agent: agent, tag: tag, opts: opts, meta: meta, restart: restart}

      {:error, message} ->
        raise Jido.Error.validation_error(message, field: :restart)
    end
  end

  @doc """
  Creates an AdoptChild directive for explicitly attaching a child to the current parent.

  ## Options

  - `:meta` - Metadata to write into the adopted child's new parent reference (map)

  ## Examples

      Directive.adopt_child(child_pid, :worker_1)
      Directive.adopt_child("child-agent-id", :worker_1, meta: %{restored: true})
  """
  @spec adopt_child(pid() | String.t(), term(), keyword()) :: AdoptChild.t()
  def adopt_child(child, tag, opts \\ [])

  def adopt_child(child, tag, opts) when is_pid(child) or is_binary(child) do
    %AdoptChild{
      child: child,
      tag: tag,
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def adopt_child(child, _tag, _opts) do
    raise Jido.Error.validation_error(
            "child must be a PID or child id string, got: #{inspect(child)}",
            field: :child
          )
  end

  @doc """
  Creates a StopChild directive to gracefully stop a tracked child agent.

  ## Examples

      Directive.stop_child(:worker_1)
      Directive.stop_child(:processor, :shutdown)
  """
  @spec stop_child(term(), term()) :: StopChild.t()
  def stop_child(tag, reason \\ :normal) do
    %StopChild{tag: tag, reason: reason}
  end

  @doc """
  Creates a Schedule directive.

  ## Examples

      Directive.schedule(5000, :timeout)
      Directive.schedule(1000, {:check, ref})
  """
  @spec schedule(non_neg_integer(), term()) :: Schedule.t()
  def schedule(delay_ms, message) do
    %Schedule{delay_ms: delay_ms, message: message}
  end

  @doc """
  Creates a RunInstruction directive.

  ## Options

  - `:result_action` - Internal action atom/module to receive execution results (default: `:instruction_result`)
  - `:meta` - Optional metadata echoed in result payload (map)

  ## Examples

      Directive.run_instruction(instruction)
      Directive.run_instruction(instruction, result_action: :fsm_instruction_result)
  """
  @spec run_instruction(Jido.Instruction.t(), keyword()) :: RunInstruction.t()
  def run_instruction(%Jido.Instruction{} = instruction, opts \\ []) do
    %RunInstruction{
      instruction: instruction,
      result_action: Keyword.get(opts, :result_action, :instruction_result),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @doc """
  Creates a Stop directive.

  ## Examples

      Directive.stop()
      Directive.stop(:shutdown)
  """
  @spec stop(term()) :: Stop.t()
  def stop(reason \\ :normal) do
    %Stop{reason: reason}
  end

  @doc """
  Creates a Cron directive for recurring scheduled execution.

  ## Options

  - `:job_id` - Logical id for the job (for upsert/cancel)
  - `:timezone` - Timezone identifier

  ## Examples

      Directive.cron("* * * * *", tick_signal)
      Directive.cron("@daily", cleanup_signal, job_id: :daily_cleanup)
      Directive.cron("0 9 * * MON", weekly_signal, job_id: :monday_9am, timezone: "America/New_York")
  """
  @spec cron(term(), term(), keyword()) :: Cron.t()
  def cron(cron_expr, message, opts \\ []) do
    %Cron{
      cron: cron_expr,
      message: message,
      job_id: Keyword.get(opts, :job_id),
      timezone: Keyword.get(opts, :timezone)
    }
  end

  @doc """
  Creates a CronCancel directive to stop a recurring job.

  ## Examples

      Directive.cron_cancel(:heartbeat)
      Directive.cron_cancel(:daily_cleanup)
  """
  @spec cron_cancel(term()) :: CronCancel.t()
  def cron_cancel(job_id) do
    %CronCancel{job_id: job_id}
  end

  # ============================================================================
  # Multi-Agent Communication Helpers
  # ============================================================================

  @doc """
  Creates an Emit directive targeting a specific process by PID.

  This is a convenience for sending signals directly to another agent or process.

  ## Options

  All options are passed to the `:pid` dispatch adapter:
  - `:delivery_mode` - `:async` (default) or `:sync`
  - `:timeout` - Timeout for sync delivery (default: 5000)

  ## Examples

      Directive.emit_to_pid(signal, some_pid)
      Directive.emit_to_pid(signal, worker_pid, delivery_mode: :sync)
  """
  @spec emit_to_pid(term(), pid(), Keyword.t()) :: Emit.t()
  def emit_to_pid(signal, pid, extra_opts \\ []) when is_pid(pid) do
    opts = Keyword.merge([target: pid], extra_opts)
    %Emit{signal: signal, dispatch: {:pid, opts}}
  end

  @doc """
  Creates an Emit directive targeting the agent's parent.

  The agent's state must have a `__parent__` field containing a `ParentRef` struct.
  This field is automatically populated when an agent is spawned via the
  `SpawnAgent` directive or explicitly reattached via `AdoptChild`.

  Returns `nil` if the agent has no current parent. Orphaned agents clear
  `__parent__` during the orphan transition, so `emit_to_parent/3` becomes
  unavailable until the child is explicitly adopted again. Former parent
  provenance remains available via `agent.state.__orphaned_from__`, but that
  field is intentionally not used for routing. Use `List.wrap/1` to safely
  handle the result when building directive lists.

  ## Options

  Same as `emit_to_pid/3`.

  ## Examples

      # In a child agent's action:
      defmodule WorkDoneAction do
        use Jido.Action, name: "work.done", schema: []

        def run(_params, context) do
          reply = Signal.new!("worker.result", %{answer: 42}, source: "/worker")
          directive = Directive.emit_to_parent(context.agent, reply)
          {:ok, %{}, List.wrap(directive)}
        end
      end

      # With sync delivery
      Directive.emit_to_parent(agent, signal, delivery_mode: :sync)
  """
  @spec emit_to_parent(struct(), term(), Keyword.t()) :: Emit.t() | nil
  def emit_to_parent(agent, signal, extra_opts \\ [])

  def emit_to_parent(
        %{state: %{__parent__: %Jido.AgentServer.ParentRef{pid: pid}}},
        signal,
        extra_opts
      )
      when is_pid(pid) do
    emit_to_pid(signal, pid, extra_opts)
  end

  def emit_to_parent(_agent, _signal, _extra_opts), do: nil
end
