defmodule Jido.AgentServer do
  @moduledoc """
  A small, in-memory process for serial Agent turns.

  Turn calls wait for five seconds by default. A caller timeout does not cancel
  a turn. A separate admission deadline can expire queued work before it starts.
  Each turn runs in an owned Runic Runner Worker. Reads stay
  available while a turn runs. Calls run in order. A returned error keeps the
  saved Agent and revision, but it cannot undo external I/O. State lives only
  as long as its activation lives. An activation-owned checkpoint restores the
  last published Agent and revision after worker failure. It is local memory,
  not durable storage, and does not replay turns or post-commit effects.

  `turn_timeout:` defaults to 60,000 ms and covers all active work before commit.
  Timeout and cancellation stop owned work before replying or starting another
  turn. They preserve the saved Agent and revision, but cannot undo external I/O.

  Set the application default with
  `config :jido, Jido.AgentServer, turn_timeout: 60_000`.
  An explicit startup option overrides this setting. The setting is read at
  startup and does not change an existing server. Caller wait and queue
  admission limits are separate.

  `exec_opts:` sets per-node `timeout:`, `max_attempts:`, `backoff:`,
  `base_delay_ms:`, `max_delay_ms:`, `max_concurrency:`, and Runic `hooks:`.
  Defaults are no node deadline, one attempt, no backoff, 500/30,000 ms delay
  bounds, and one concurrent node. Retries require `Jido.Action.Error.retryable?/1`.
  The outer turn deadline includes retries and cleanup. Hooks run synchronously
  in the Worker; keep them short and do not call Worker APIs from them.
  Hook exceptions use a safe warning and leave execution unchanged.

  `error_policy:` accepts `:log_only` (continue), `:stop_on_error`,
  `{:max_errors, positive_integer}`, `{:emit_signal, dispatch_config}`, or a
  two-argument callback receiving the error and terminal summary. A callback
  returns `:continue` or `{:stop, atom}`. Dispatch and callbacks run after cleanup
  in a separate task with `error_policy_timeout:` (default 5,000 ms, finite).
  They hold queued turns, but permit reads. Their failure stops the server and
  preserves the turn error. The consecutive error count resets on success;
  cancellation and whole-turn timeout do not increment it. Error Signals contain
  only the summary. Incoming `jido.agent_server.error` Signals cannot emit another.

  `status/1` includes `last_outcome`. `debug: true` also retains terminal summaries
  for `history/1`, with `debug_max_events:` (default 100, range 1..10,000).
  Summaries contain IDs, outcome, stage, commit flag, revisions, directive count,
  and duration. They exclude raw errors, Agent state, Signal data, and context.
  Telemetry uses the `[:jido, :agent_server]` prefix. Turn trace context reaches
  lifecycle tasks, Action context, and native Task Logger metadata. Abrupt kills
  cannot emit a shutdown or terminal event.

  `child_spec/1` supervises an activation root with transient restart. The root
  owns this worker and required Plugin roots in one `:one_for_all` group.
  `start/1` and instance lookup return the request worker; `activation/1` returns
  its supervisor. `Jido.AgentServer.Supervisor.start_link/1` returns `{:ok, root}` for
  standalone supervision. Explicit stop confirms the complete root's death.
  Recovery uses the last published Agent and revision with fresh readiness.
  Recovery waits for the previous turn's Runic scope to close before
  admitting work, within the readiness budget. A Plugin supervisor can recover
  its internal workers locally.
  Runtime relationship metadata survives worker recovery in a supervisor-owned
  ETS table. Whole activation replacement restores only saved composition
  intent. A restarted owned-child DynamicSupervisor starts empty; accepted
  topology declarations rebuild the child set.

  Use `start(agent: instance, jido: MyJido, partition: "tenant")` for instance
  supervision. It shares that instance's Runner, claims its Registry identity,
  and stops if instance ownership is lost. `whereis/3` looks up AgentServer;
  `Jido.whereis_agent/3` also finds it. `Jido.start_agent/3` starts the same
  activation. Worker OTP names can be local, global, or via. An instance
  registration exists alongside that name. `start_link/1` is the low-level
  bare-worker API and rejects runtime Plugins. Use `child_spec/1` or `start/1`
  for the uniform activation lifecycle, including Agents with no Plugins.

  Set instance defaults with `Jido.start_link(name: MyJido,
  agent_server: [turn_timeout: 60_000])`. Explicit server options override instance
  defaults, then application defaults, then built-in defaults. Settings are fixed
  at startup. The shared instance Runner and standalone Runners use `Store`.

  Directives are validated as a complete batch before commit. The default
  `max_directives_per_turn:` is 1,000; use a non-negative integer or `:infinity`.
  `Emit` uses explicit dispatch first. Otherwise it uses accepted topology
  connections, its owning topology, `default_dispatch:`, or a cast to this server. Bus dispatch inherits the instance unless its scope is explicit.
  Cast acceptance does not confirm admission, commit, or delivery. Trace and
  causation follow the source Signal. `ServerStop` must be last. `ErrorReport` applies the
  failure policy after commit. `ProcessStart` requires a Jido instance and starts
  an untracked child under its supervisor; that child can outlive this server.
  Topology and Plugin changes are applied to the candidate before commit.
  One accepted revision holds the complete target. After save, the supervisor
  rebuilds changed Plugin resources before another turn. `await_ready/2` waits
  for this step. Reads and the commit reply can precede readiness. A resource
  startup failure stops the supervisor; recovery uses the saved target.
  Declared local agents and buses run under the owning supervisor. Counts and
  initial inputs bind from accepted state. Changed definitions or bound inputs
  replace affected agents; unchanged slots retain their processes. Connection
  edits retain processes. Remote startup and unknown runtime endpoint kinds
  fail validation before commit. Topology agents use permanent supervision.

  `snapshot/2` returns `%{agent: agent, state_version: revision}` from one server
  event. It is a live value; `Jido.Persistence.snapshot/2` converts it to portable
  data. `upgrade/3` runs an explicit snapshot upgrade Action in serial order and
  uses the normal validation, quiescence, save, checkpoint and reconciliation
  boundary. It returns `{:ok, candidate, []}` after commit. Use `await_ready/2`
  to wait for process changes. Snapshot reads during startup return `:not_ready`.

  Existing runtime Plugins must implement idempotent `quiesce/2` and `resume/2`
  before a live configuration change is accepted. A failed pre-commit change
  resumes old resources. New roots rebuild from the accepted state and revision.
  New, removed, or reconfigured Plugins do not receive `after_commit/3` for that
  configuration commit. Unchanged Plugins retain their normal hooks.

  Plugin-owned custom directives use
  `directive_handler: fn directive, context -> :ok | {:error, reason} end`.
  Other built-in directives remain rejected.
  The handler receives the committed Agent, revision, server PID, instance,
  partition, turn id, and source Signal id. Existing Plugin ownership rules apply.

  Commit success is sent before effects start. Effects run in order in linked
  tasks before the next turn. Reads remain available. `directive_timeout:` is a
  separate finite deadline for the whole batch, default 5,000 ms. On error or
  timeout, the batch stops and the committed state and success reply remain valid.
  `status.effects` reports progress; `status.last_effect_outcome` reports the batch
  result without raw errors. Effects cannot be cancelled with pre-commit cancel.
  Plugin `after_commit/3` callbacks run in declaration order before directives,
  including commits with no directives. `commit_timeout:` defaults to 5,000 ms
  and bounds the complete hook batch separately from `directive_timeout:`.
  A hook failure stops later hooks and directives, preserving the commit.
  Declared Plugin directives use `dispatch/4` with the live runtime reference
  and a narrow committed context. A custom handler remains a fallback when no
  live Plugin dispatcher is declared.

  Stop the server to stop active effects. Handlers must finish child work before
  returning and keep it linked while they run. Work that continues after a
  callback returns is outside this ownership guarantee. Use a Plugin runtime
  tree for work that must remain owned by this activation.

  Declared Plugin runtime trees start under an owned supervisor. Startup and
  readiness run outside the server. `agent/1`, `status/1`, and Plugin state reads
  stay available; turns return `{:error, :not_ready}` until `await_ready/2` succeeds.
  `readiness_timeout:` is a separate finite startup budget, default 5,000 ms.
  Caller wait timeout does not cancel startup. All roots start before readiness
  checks run in declaration order. Startup failure stops provisional trees.
  Child-start functions must return within a bounded time. Long startup work
  belongs in readiness. A deadline rejects work immediately; cleanup settles an
  already-running supervisor start before it completes. Arbitrary child-start
  functions that never return cannot be cancelled safely by an OTP supervisor.
  Required root loss restarts the recovery group with fresh references.
  Live Plugin admission follows pure preparation, in declaration order, within
  the turn deadline. Each Plugin can reject or return only its transient runtime
  input. It cannot replace the Agent, Signal, caller context, or prepared input.

  Persistence is disabled by default. Set `persistence:` to an adapter or
  `:inherit` to use the Jido instance adapter. This requires an activation and
  a stable instance namespace. `persistence_mode: :create` creates revision zero
  before readiness and rejects an existing record. Use `:restore` to require an
  existing compatible record. Missing or invalid records never select fresh state.
  `persistence_timeout:` is a separate finite storage budget, default 5,000 ms.
  Startup reads can show the supplied Agent until `await_ready/2` succeeds.

  Required writes run in the `:saving` stage before local publication and success.
  Reads stay available and new turns wait. Caller timeout does not cancel a write;
  cancellation returns `{:error, :commit_in_progress}` during save. A failed or
  uncertain write ends the activation without success, hooks, or directives.
  Timeout means an unknown write outcome; stopping a local task cannot undo a
  remote write. Explicit restore reads the storage result before work can resume.
  Worker recovery also reloads storage, which can be ahead of the local checkpoint.

  Existing Agent and Plugin checkpoint conversion applies at the portable save
  boundary. Restore validates exact definition/version before Plugin resources
  start. No implicit migration, turn replay, effect replay, or family restore occurs.
  `quiesce/2` closes admission, rejects queued turns, and waits for owned work
  and effects. Its default policy finishes the turn; `active: :cancel` cancels
  pre-commit work. Required saves and post-commit work must finish. Reads remain
  available. A finite control deadline leaves admission closed on timeout.
  `resume/2` opens a settled activation. Worker recovery retains closed admission.

  `attach/3` and `detach/3` track owner PIDs once per activation. Owner DOWN
  removes an attachment. Runtime owners and admission are not checkpoint data.
  `idle_timeout:` defaults to `:infinity`. A finite idle budget starts when the
  Agent is ready, idle, open, and has no owners. Turns and `touch/1` reset it;
  reads do not. The default `idle_policy: :stop` performs no extra save.
  `idle_policy: :hibernate` requires persistence and saves before stopping.

  `hibernate/2` quiesces, saves the current revision, and confirms activation
  exit. Storage uses the smaller of the control budget and persistence_timeout.
  On save failure the Agent remains live with an explicit resumable? result.
  Known no-write failure restores prior admission. Conflict or uncertainty
  blocks resume, including across worker recovery. A failed automatic save
  closes admission and needs an explicit operator decision. These controls act
  on one activation; they do not quiesce independent or owned child Agents.

  The adapter's storage determines durability. ETS survives activation loss but
  does not survive a BEAM restart. Revision checks are not a writer lease.
  """

  @behaviour :gen_statem

  @type server :: :gen_statem.server_ref()
  @type signal_result :: {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}

  @max_timeout 4_294_967_295
  @runtime_defaults [
    turn_timeout: 60_000,
    exec_opts: [],
    error_policy: :log_only,
    error_policy_timeout: 5_000,
    debug: false,
    debug_max_events: 100,
    max_postponed_signals: 1_000,
    max_directives_per_turn: 1_000,
    directive_timeout: 5_000,
    directive_handler: nil,
    default_dispatch: nil,
    readiness_timeout: 5_000,
    commit_timeout: 5_000,
    persistence: false,
    persistence_mode: :create,
    persistence_timeout: 5_000,
    idle_timeout: :infinity,
    idle_policy: :stop
  ]
  @runtime_keys Keyword.keys(@runtime_defaults)
  @startup_keys @runtime_keys ++ [:agent, :name, :runner, :jido, :partition]
  @exec_keys [
    :timeout,
    :max_attempts,
    :backoff,
    :base_delay_ms,
    :max_delay_ms,
    :max_concurrency,
    :hooks
  ]
  @hook_arities [
    on_dispatch: 2,
    on_complete: 3,
    on_failed: 3,
    on_idle: 1,
    on_persistence_error: 3,
    transform_runnables: 2
  ]
  @error_signal "jido.agent_server.error"

  require Logger

  alias Jido.Agent
  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.Emit
  alias Jido.AgentServer.TopologyRuntime
  alias Jido.AgentServer.Directive.{AgentStart, AgentStop, AgentSend, OwnerSend}
  alias Jido.AgentServer.Directive.ErrorReport
  alias Jido.AgentServer.Directive.ProcessStart
  alias Jido.AgentServer.Directive.ServerStop
  alias Jido.AgentServer.Plugin.Callbacks
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias Jido.Dispatch.Preparation, as: DispatchPreparation
  alias Jido.Agent.Command
  alias Jido.Agent.Runner, as: AgentRunner
  alias Jido.Signal
  alias Jido.Telemetry.Semantic
  alias Jido.Tracing.Context, as: TraceContext
  alias Runic.Runner

  defmodule CompositionRuntime do
    @moduledoc false
    alias Jido.Agent.{Error, Mutation}
    alias Jido.AgentServer, as: Server

    def check(data, candidate, directives) do
      changed = Mutation.changed_plugins(data.agent, candidate, directives)

      cond do
        is_nil(data.activation) and
            (not Jido.Agent.Topology.empty?(candidate.topology) or
               Jido.AgentServer.TopologyRuntime.buses(candidate) != [] or changed != []) ->
          {:error, :activation_required}

        true ->
          with :ok <- validate_runtime(%{data | agent: candidate}) do
            Enum.reduce_while(data.plugin_specs, :ok, fn spec, :ok ->
              if spec.module in changed and match?(%{runtime?: true}, spec.agent_server) and
                   not (function_exported?(spec.module, :quiesce, 2) and
                          function_exported?(spec.module, :resume, 2)) do
                {:halt,
                 Error.fail(
                   :plugin_quiescence_required,
                   [:extensions],
                   "Plugin changes require quiesce and resume callbacks",
                   %{plugin: spec.module}
                 )}
              else
                {:cont, :ok}
              end
            end)
          end
      end
    end

    def validate_runtime(data), do: Jido.AgentServer.TopologyRuntime.validate(data.agent)

    def pause(specs, refs, callback) do
      Enum.reduce_while(specs, :ok, fn spec, :ok ->
        result =
          bounded(fn ->
            Jido.Plugin.Error.safe_apply(
              spec.module,
              spec.module,
              callback,
              [Map.get(refs, spec.module), spec.agent_server.options],
              "Plugin configuration boundary failed"
            )
          end)

        if result == :ok,
          do: {:cont, :ok},
          else: {:halt, {:error, {callback, spec.module, result}}}
      end)
    end

    defp bounded(fun) do
      task = Task.async(fun)

      case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> {:error, :plugin_control_timeout}
      end
    end

    def plugins(data, owner, changed) do
      with :ok <-
             Enum.reduce_while(changed, :ok, fn module, :ok ->
               case remove_spec(data.activation, {:plugin, module}) do
                 :ok -> {:cont, :ok}
                 error -> {:halt, error}
               end
             end),
           {:ok, refs} <- Server.bootstrap_current_plugins(data, owner) do
        {:ok, refs}
      end
    end

    def reconcile(data), do: Jido.AgentServer.TopologyRuntime.reconcile(data)

    defp remove_spec(root, id) do
      case Supervisor.terminate_child(root, id) do
        :ok -> Supervisor.delete_child(root, id)
        {:error, :not_found} -> :ok
      end
    end
  end

  defmodule Pending do
    @moduledoc false
    @enforce_keys [:request_id, :owner]
    @derive {Inspect, only: []}
    defstruct [:request_id, :owner]
  end

  defmodule Store do
    @moduledoc false
    @behaviour Runic.Runner.Store
    # AgentServer owns the committed Agent. Turn execution is not durable.
    @impl true
    def init_store(_opts), do: {:ok, nil}
    @impl true
    def save(_id, _log, _state), do: :ok
    @impl true
    def load(_id, _state), do: {:error, :not_found}
    @impl true
    def list(_state), do: {:ok, []}
    @impl true
    def exists?(_id, _state), do: false
  end

  @opaque pending :: %Pending{request_id: :gen_statem.request_id(), owner: pid()}

  @doc "Returns a child specification for OTP supervision."
  def child_spec(opts) do
    agent = Keyword.fetch!(opts, :agent)

    %{
      id: {__MODULE__, opts[:jido], opts[:partition], agent.id},
      start: {ServerSupervisor, :start_link, [opts]},
      restart: :transient,
      type: :supervisor,
      shutdown: :infinity
    }
  end

  @doc "Starts a registered AgentServer under the selected Jido instance supervisor."
  def start(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and not is_nil(opts[:jido]) do
      with {:ok, opts} <- runtime_options(opts),
           :ok <- validate_options(opts),
           {:ok, _agent} <- Jido.Agent.Validation.validate_instance(opts[:agent]) do
        case start_activation(
               Jido.agent_supervisor_name(opts[:jido]),
               child_spec(opts)
             ) do
          {:error, {:shutdown, {:failed_to_start_child, __MODULE__, {:already_started, pid}}}} ->
            {:error, {:already_started, pid}}

          result ->
            result
        end
      end
    else
      invalid_options("start requires a Jido instance")
    end
  catch
    :exit, _ -> invalid_options("Jido instance is not available")
  end

  def start(_), do: invalid_options("options must be a keyword list")

  @doc "Looks up an AgentServer in one instance and partition. Returns nil when absent."
  def whereis(jido, id, opts \\ []) do
    with true <- is_atom(jido) and not is_nil(jido) and is_binary(id),
         true <-
           is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- [:partition] == [],
         true <- valid_partition?(opts[:partition]),
         [{pid, :ready}] <-
           Registry.lookup(Jido.registry_name(jido), registry_key(id, opts[:partition])),
         true <- alive?(pid) do
      pid
    else
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Returns true for a live local AgentServer PID or OTP name."
  def alive?(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) and node(pid) == node() ->
        Process.alive?(pid) and :proc_lib.translate_initial_call(pid) == {__MODULE__, :init, 1}

      _ ->
        false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc """
  Starts a bare worker with one validated Agent instance and a running `runner:`.
  Runtime Plugins require an activation. Prefer `child_spec/1` or `start/1`.
  Bare-worker standalone use requires the nested Store module. `jido:` selects the live
  instance's Runner, Store, and registration. Turns are local and temporary.
  `max_postponed_signals:` defaults to 1,000; use a non-negative integer or
  `:infinity`. This bounds postponed turns, not the process mailbox.
  `turn_timeout:` defaults to 60,000 ms; use `0..4_294_967_295` or `:infinity`.
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) when is_list(opts) do
    with {:ok, opts} <- activation_options(opts),
         {:ok, specs} <-
           Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(opts[:agent])) do
      if not Jido.Agent.Topology.empty?(opts[:agent].topology) or
           TopologyRuntime.buses(opts[:agent]) != [] or
           opts[:persistence] not in [nil, false] or
           Enum.any?(specs, &match?(%{agent_server: %{runtime?: true}}, &1)) do
        invalid_options("runtime Plugins require a supervisor; use child_spec/1 or start/1")
      else
        start_worker(opts, nil)
      end
    end
  end

  def start_link(_opts), do: invalid_options("options must be a keyword list")

  @doc false
  def activation_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, opts} <- runtime_options(opts),
           :ok <- validate_options(opts),
           {:ok, agent} <- Jido.Agent.Validation.validate_instance(Keyword.fetch!(opts, :agent)),
           :ok <- Agent.validate_runtime_support(agent),
           do: {:ok, Keyword.put(opts, :agent, agent)}
    else
      invalid_options("options must be a keyword list")
    end
  end

  def activation_options(_), do: invalid_options("options must be a keyword list")

  @doc false
  def start_worker(opts, activation) do
    initial = {Keyword.fetch!(opts, :agent), Keyword.put(opts, :activation, activation)}

    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, initial, [])
      name when is_atom(name) -> :gen_statem.start_link({:local, name}, __MODULE__, initial, [])
      name -> :gen_statem.start_link(name, __MODULE__, initial, [])
    end
  end

  defp normalize_stop_reason(reason) when reason in [:normal, :shutdown], do: reason
  defp normalize_stop_reason({:shutdown, _} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp runtime_options(opts) do
    with {:ok, opts} <- instance_options(opts),
         {:ok, opts} <- with_turn_timeout(opts),
         do: {:ok, Keyword.merge(@runtime_defaults, opts)}
  end

  defp instance_options(opts) do
    case Keyword.get(opts, :jido) do
      nil ->
        if is_nil(opts[:partition]),
          do: {:ok, opts},
          else: invalid_options("partition requires a Jido instance")

      jido when is_atom(jido) ->
        with pid when is_pid(pid) <- Process.whereis(jido),
             {:supervisor, Jido, 1} <- :proc_lib.translate_initial_call(pid),
             true <- instance_children_live?(pid, jido),
             runner = Jido.exec_runner_name(jido),
             true <- Keyword.get(opts, :runner, runner) == runner,
             true <- valid_partition?(opts[:partition]) do
          {:ok,
           Jido.instance_agent_server_options(jido)
           |> Keyword.merge(opts)
           |> Keyword.put(:runner, runner)}
        else
          _ -> invalid_options("invalid Jido instance, partition, or Runner ownership")
        end

      _ ->
        invalid_options("jido must name a running instance")
    end
  end

  defp instance_children_live?(pid, jido) do
    children = Supervisor.which_children(pid)

    Enum.all?(
      [
        Jido.registry_name(jido),
        Jido.agent_supervisor_name(jido),
        Jido.registration_guard_name(jido)
      ],
      fn name ->
        child = Process.whereis(name)
        is_pid(child) and Enum.any?(children, fn {_, pid, _, _} -> pid == child end)
      end
    )
  end

  defp valid_partition?(nil), do: true
  defp valid_partition?(value), do: is_binary(value) and byte_size(value) > 0
  defp registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}

  defp valid_name?(nil), do: true
  defp valid_name?(name) when is_atom(name), do: true
  defp valid_name?({:global, _}), do: true

  defp valid_name?({:via, module, _}) when is_atom(module) and not is_nil(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :register_name, 2)

  defp valid_name?(_), do: false

  @doc false
  def validate_defaults(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- @runtime_keys == [] do
      validate_runtime(Keyword.merge(@runtime_defaults, opts))
    else
      invalid_options("invalid instance AgentServer defaults")
    end
  end

  defp with_turn_timeout(opts) do
    if Keyword.has_key?(opts, :turn_timeout) do
      {:ok, opts}
    else
      config = Application.get_env(:jido, __MODULE__, [])

      cond do
        not is_list(config) or not Keyword.keyword?(config) ->
          invalid_options("AgentServer application configuration must be a keyword list")

        Keyword.keys(config) -- [:turn_timeout] != [] ->
          invalid_options("unknown AgentServer application configuration options")

        true ->
          {:ok,
           Keyword.put(
             opts,
             :turn_timeout,
             Keyword.get(config, :turn_timeout, @runtime_defaults[:turn_timeout])
           )}
      end
    end
  end

  defp validate_options(opts) do
    name = Keyword.get(opts, :name)

    cond do
      Keyword.keys(opts) -- @startup_keys != [] ->
        invalid_options("unknown startup options")

      not Keyword.has_key?(opts, :agent) ->
        invalid_options("expected :agent option")

      opts[:persistence] not in [nil, false] and is_nil(opts[:jido]) ->
        invalid_options("persistence requires a Jido instance with a stable namespace")

      not valid_name?(name) ->
        invalid_options("invalid OTP name")

      not is_atom(Keyword.get(opts, :runner)) or is_nil(Keyword.get(opts, :runner)) ->
        invalid_options("expected a named Runic Runner in :runner")

      is_nil(Process.whereis(Keyword.fetch!(opts, :runner))) ->
        invalid_options("Runner is not running")

      true ->
        with :ok <- validate_runner(Keyword.fetch!(opts, :runner), opts[:jido]),
             do: validate_runtime(opts)
    end
  end

  defp validate_runtime(opts) do
    with :ok <- validate_timeout(opts, :turn_timeout, false),
         :ok <- validate_exec(opts[:exec_opts]),
         :ok <- validate_error_policy(opts[:error_policy]),
         :ok <- validate_timeout(opts, :error_policy_timeout),
         :ok <- validate_timeout(opts, :directive_timeout),
         :ok <- validate_timeout(opts, :readiness_timeout),
         :ok <- validate_timeout(opts, :commit_timeout),
         :ok <- validate_timeout(opts, :persistence_timeout),
         :ok <- validate_timeout(opts, :idle_timeout, false),
         :ok <- validate_setting(opts[:idle_policy] in [:stop, :hibernate], :idle_policy),
         :ok <-
           validate_setting(
             opts[:idle_policy] != :hibernate or opts[:persistence] not in [nil, false],
             :idle_policy
           ),
         :ok <-
           validate_setting(opts[:persistence_mode] in [:create, :restore], :persistence_mode),
         :ok <- validate_limit(opts, :max_postponed_signals),
         :ok <- validate_limit(opts, :max_directives_per_turn),
         :ok <-
           validate_setting(
             is_nil(opts[:directive_handler]) or is_function(opts[:directive_handler], 2),
             :directive_handler
           ),
         :ok <-
           validate_setting(validate_dispatch(opts[:default_dispatch]) == :ok, :default_dispatch),
         :ok <- validate_setting(is_boolean(opts[:debug]), :debug),
         do:
           validate_setting(
             is_integer(opts[:debug_max_events]) and opts[:debug_max_events] in 1..10_000,
             :debug_max_events
           )
  end

  defp validate_timeout(opts, key, finite? \\ true) do
    value = Keyword.fetch!(opts, key)
    validate_setting((not finite? or value != :infinity) and validate_wait(value) == :ok, key)
  end

  defp validate_limit(opts, key) do
    value = Keyword.fetch!(opts, key)
    validate_setting(value == :infinity or (is_integer(value) and value >= 0), key)
  end

  defp validate_setting(true, _key), do: :ok
  defp validate_setting(false, key), do: invalid_options("invalid #{key}")

  defp validate_dispatch(nil), do: :ok

  defp validate_dispatch(dispatch) do
    case Signal.Dispatch.validate_opts(dispatch) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_dispatch}
    end
  catch
    _, _ -> {:error, :invalid_dispatch}
  end

  defp validate_exec(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- @exec_keys == [] and
         Enum.all?(opts, fn {key, value} -> valid_exec?(key, value) end),
       do: :ok,
       else: invalid_options("invalid exec_opts")
  end

  defp valid_exec?(:timeout, value), do: validate_wait(value) == :ok

  defp valid_exec?(key, value) when key in [:base_delay_ms, :max_delay_ms],
    do: value != :infinity and validate_wait(value) == :ok

  defp valid_exec?(key, value) when key in [:max_attempts, :max_concurrency],
    do: is_integer(value) and value > 0

  defp valid_exec?(:backoff, value), do: value in [:none, :linear, :exponential, :jitter]

  defp valid_exec?(:hooks, hooks) do
    is_list(hooks) and Keyword.keyword?(hooks) and
      Enum.all?(hooks, fn {key, fun} ->
        case Keyword.fetch(@hook_arities, key) do
          {:ok, arity} -> is_function(fun, arity)
          :error -> false
        end
      end)
  end

  defp validate_error_policy(policy) when policy in [:log_only, :stop_on_error], do: :ok
  defp validate_error_policy({:max_errors, count}) when is_integer(count) and count > 0, do: :ok
  defp validate_error_policy(fun) when is_function(fun, 2), do: :ok

  defp validate_error_policy({:emit_signal, target}) do
    case Jido.Signal.Dispatch.validate_opts(target) do
      {:ok, _} -> :ok
      {:error, _} -> invalid_options("invalid error_policy Signal destination")
    end
  end

  defp validate_error_policy(_), do: invalid_options("invalid error_policy")

  defp validate_runner(runner, _jido) do
    with pid when is_pid(pid) <- Process.whereis(runner),
         {:supervisor, Runner, 1} <- :proc_lib.translate_initial_call(pid),
         true <- live_runner_children?(runner, pid),
         {store, _state} <- Runner.get_store(runner),
         true <-
           store == Store do
      :ok
    else
      _other -> invalid_options("Runner must be running with Jido.AgentServer.Store")
    end
  rescue
    ArgumentError -> invalid_options("Runner configuration is unavailable")
  catch
    :exit, _reason -> invalid_options("Runner is not available")
  end

  defp live_runner_children?(runner, pid) do
    children = Supervisor.which_children(pid)

    Enum.all?([Registry, TaskSupervisor, WorkerSupervisor], fn suffix ->
      name = Module.concat(runner, suffix)

      Enum.any?(children, fn
        {^name, child, :supervisor, _modules} when is_pid(child) ->
          Process.whereis(name) == child

        _child ->
          false
      end)
    end)
  end

  defp invalid_options(message),
    do: {:error, Jido.Error.validation_error(message, kind: :config)}

  @doc "Stops the server and its active turn through OTP termination."
  @spec stop(:gen_statem.server_ref(), term(), timeout()) :: :ok
  def stop(server, reason \\ :shutdown, timeout \\ 5_000) do
    deadline =
      if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    reason =
      case reason do
        :normal -> :normal
        :shutdown -> :shutdown
        {:shutdown, _} -> reason
        other -> {:shutdown, other}
      end

    case :gen_statem.call(server, :stop_target, remaining_wait(deadline)) do
      {:error, _} = error ->
        error

      nil ->
        :gen_statem.stop(server, reason, remaining_wait(deadline))

      root ->
        ref = Process.monitor(root)

        try do
          :gen_statem.stop(server, reason, remaining_wait(deadline))
          await_activation_down(root, ref, deadline, {:stop, [server, reason, timeout]})
          :ok
        after
          Process.demonitor(ref, [:flush])
        end
    end
  end

  defp await_activation_down(root, ref, deadline, {operation, args}) do
    receive do
      {:DOWN, ^ref, :process, ^root, _} -> :ok
    after
      remaining_wait(deadline) -> exit({:timeout, {__MODULE__, operation, args}})
    end
  end

  defp remaining_wait(:infinity), do: :infinity
  defp remaining_wait(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  @doc """
  Cancels the active turn and waits for owned work to stop. Returns `:ok` when
  cleanup is confirmed, or `{:error, :not_running}` when idle. The turn caller
  receives `{:error, :cancelled}`. Caller wait timeout exits the caller, as with
  OTP calls; it does not undo cancellation.
  Calls from owned work return `{:error, :reentrant_turn}`.
  """
  @spec cancel(:gen_statem.server_ref(), timeout()) :: :ok | {:error, term()}
  def cancel(server, timeout \\ 5_000), do: cancel_request(server, :active, timeout)

  @doc """
  Cancels only the active turn with this ID. A different active ID returns
  `{:error, :stale_turn}`. An idle server returns `{:error, :not_running}`.
  Successful cancellation confirms cleanup, as with `cancel/2`.
  """
  @spec cancel_turn(:gen_statem.server_ref(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000) when is_binary(turn_id),
    do: cancel_request(server, turn_id, timeout)

  defp cancel_request(server, id, timeout) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, {:cancel, id}, timeout)
  end

  @doc """
  Closes admission and rejects queued turns with `:quiesced`. Waits for the
  active turn and post-commit work. Set `active: :cancel` to cancel pre-commit
  work; accepted saves and effects must finish. Reads remain available.
  `timeout:` is a finite control budget (default 5,000 ms). On expiry admission
  stays closed. Caller wait allows a further 1,000 ms for the control reply;
  an unresponsive server causes an OTP timeout exit. Call `resume/2` after the
  server settles. Owned callbacks cannot
  call this synchronous control.
  """
  def quiesce(server, opts \\ []), do: control_request(server, :quiesce, opts)

  @doc "Opens admission after quiescence. An uncertain hibernation save forbids resume."
  def resume(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, :resume, timeout)
  end

  @doc """
  Saves the settled Agent at its current revision, then stops the activation.
  Requires configured persistence. Success confirms activation exit. Accepts the
  same options as `quiesce/2`; cleanup has a further `timeout:` wait budget.
  Failure returns `{:error, %{reason: reason, resumable?: boolean}}`. A known
  no-write failure restores prior admission. Conflict or uncertainty keeps the
  live Agent closed and forbids resume. Required turn writes still follow their
  separate fail-stop contract.
  """
  def hibernate(server, opts \\ []) do
    with :ok <- validate_control_options(opts),
         target when is_pid(target) <- :gen_statem.call(server, :stop_target) do
      ref = Process.monitor(target)

      try do
        case control_request(server, :hibernate, opts) do
          :saved ->
            deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :timeout, 5_000)
            await_activation_down(target, ref, deadline, {:hibernate, [server, opts]})

          result ->
            result
        end
      after
        Process.demonitor(ref, [:flush])
      end
    else
      nil -> hibernate_error(:activation_required, true)
      error -> error
    end
  end

  defp validate_control_options(opts) do
    if is_list(opts) and Keyword.keyword?(opts) and
         Keyword.keys(opts) -- [:active, :timeout] == [] do
      with :ok <-
             validate_setting(Keyword.get(opts, :active, :finish) in [:finish, :cancel], :active),
           do: validate_timeout([timeout: Keyword.get(opts, :timeout, 5_000)], :timeout)
    else
      invalid_options("invalid control options")
    end
  end

  defp control_request(server, kind, opts) do
    with :ok <- validate_control_options(opts) do
      timeout = Keyword.get(opts, :timeout, 5_000)
      # Allow the server to report its control deadline. The caller still has
      # a finite OTP wait if delivery or the server itself cannot progress.
      wait = min(@max_timeout, timeout + 1_000)

      :gen_statem.call(
        server,
        {:control, kind, Keyword.get(opts, :active, :finish), timeout},
        wait
      )
    end
  end

  @doc "Attaches one owner. Repeated attachment is idempotent and prevents idle expiry."
  def attach(server, owner \\ self(), timeout \\ 5_000),
    do: owner_request(server, :attach, owner, timeout)

  @doc "Detaches one owner. The last detach starts a new idle budget."
  def detach(server, owner \\ self(), timeout \\ 5_000),
    do: owner_request(server, :detach, owner, timeout)

  defp owner_request(server, kind, owner, timeout) do
    with :ok <- validate_setting(is_pid(owner), :owner),
         :ok <- validate_wait(timeout),
         do: :gen_statem.call(server, {kind, owner}, timeout)
  end

  @doc "Restarts the idle budget. Does not open closed admission."
  def touch(server), do: :gen_statem.call(server, :touch)

  @doc "Returns the saved Agent instance."
  @spec agent(:gen_statem.server_ref(), timeout()) :: Agent.instance()
  def agent(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, :agent, timeout)
  end

  @doc "Returns one committed Plugin-owned state field."
  def plugin_state(server, plugin, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout),
         do: :gen_statem.call(server, {:plugin_state, plugin}, timeout)
  end

  @doc """
  Runs one Signal. Accepts a timeout or `timeout:`, `admission_timeout:`, and
  `context:` options. Admission timeout defaults to 5,000 ms; use `:infinity`
  to let queued work wait without a deadline. It is separate from caller wait.
  Finite admission deadlines require a caller on the server's node.
  Caller timeout exits the caller, as with OTP calls; it does not cancel work.
  Finite waits must be in `0..4_294_967_295` ms. Context accepts a
  map, keyword list, or nil. It is not stored in Agent state or Signal data.
  `:turn_id` and the Agent command context keys are reserved.
  """
  @spec call(:gen_statem.server_ref(), Signal.t(), timeout() | keyword()) ::
          {:ok, Agent.instance(), [struct()]} | {:error, term()}
  def call(server, signal, timeout_or_opts \\ 5_000) do
    opts = if is_list(timeout_or_opts), do: timeout_or_opts, else: [timeout: timeout_or_opts]

    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- turn_context(opts, [:timeout, :admission_timeout, :context]),
         timeout = Keyword.get(opts, :timeout, 5_000),
         :ok <- validate_wait(timeout),
         {:ok, deadline} <- admission_deadline(opts) do
      :gen_statem.call(server, turn_event(signal, context, deadline), timeout)
    end
  end

  @doc """
  Submits one turn with optional `context:` and `admission_timeout:` and returns
  a pending result handle. Admission timeout defaults to 5,000 ms. It limits
  the wait before execution, not execution itself or a later `await` call.
  Finite admission deadlines require a caller on the server's node.

  Submission does not confirm that execution has started. Use `await/2` from
  this same process to collect the result. The handle hides the OTP request.
  Invalid options return an error before submission.
  """
  @spec submit(:gen_statem.server_ref(), Signal.t(), keyword()) :: pending() | {:error, term()}
  def submit(server, signal, opts \\ []) do
    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- turn_context(opts, [:context, :admission_timeout]),
         {:ok, deadline} <- admission_deadline(opts) do
      %Pending{
        request_id: :gen_statem.send_request(server, turn_event(signal, context, deadline)),
        owner: self()
      }
    end
  end

  @doc """
  Sends one Signal without a reply, with optional `context:`.
  Delivery is best effort. A failed turn logs its ID and preserves state.
  Excess casts are dropped and logged when the postponed turn limit is reached.
  Casts have no admission deadline. Invalid options fail before sending.
  """
  @spec cast(:gen_statem.server_ref(), Signal.t(), keyword()) :: :ok | {:error, term()}
  def cast(server, signal, opts \\ []) do
    with {:ok, signal} <- Command.normalize_signal(signal),
         {:ok, context} <- turn_context(opts, [:context]) do
      :gen_statem.cast(server, turn_event(signal, context, :infinity))
    end
  end

  defp turn_event(signal, context, deadline), do: {:turn, make_ref(), signal, context, deadline}

  defp admission_deadline(opts) do
    timeout = Keyword.get(opts, :admission_timeout, 5_000)

    with :ok <- validate_wait(timeout) do
      deadline =
        if timeout == :infinity,
          do: :infinity,
          else: {node(), System.monotonic_time(:millisecond) + timeout}

      {:ok, deadline}
    end
  end

  defp admission_status(:infinity), do: :ok

  defp admission_status({origin, _deadline}) when origin != node(),
    do: {:error, :admission_clock_unavailable}

  defp admission_status({_origin, deadline}) do
    if System.monotonic_time(:millisecond) >= deadline,
      do: {:error, :admission_timeout},
      else: :ok
  end

  defp turn_context(opts, allowed) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- allowed == [] do
      with {:ok, context} <- Command.normalize_context(Keyword.get(opts, :context)),
           :ok <- Command.validate_caller_context(context) do
        if Enum.any?([:turn_id, :trace_context], &Map.has_key?(context, &1)),
          do: invalid_options(":turn_id and :trace_context are reserved"),
          else: {:ok, context}
      end
    else
      invalid_options("invalid turn options")
    end
  end

  defp validate_wait(:infinity), do: :ok
  defp validate_wait(timeout) when is_integer(timeout) and timeout in 0..@max_timeout, do: :ok

  defp validate_wait(_timeout),
    do: invalid_options("timeout must be in 0..#{@max_timeout} milliseconds or :infinity")

  @doc """
  Waits for a submitted turn and returns the same turn result as `call/3`.

  A timeout returns `{:error, :timeout}` without cancelling the turn or losing
  its reply. Call `await` again from the submitting process to keep waiting.
  A result can be collected only once. This handle is not durable and cannot
  be transferred to another process. Use `abandon/1` when its reply is no longer
  needed. Do not await a handle after collection or abandonment.
  """
  @spec await(pending(), timeout()) ::
          {:ok, Agent.instance(), [struct()]} | {:error, term()}
  def await(pending, timeout \\ 5_000)

  def await(%Pending{owner: owner, request_id: request_id}, timeout) when owner == self() do
    with :ok <- validate_wait(timeout) do
      case :gen_statem.wait_response(request_id, timeout) do
        {:reply, result} ->
          result

        :timeout ->
          {:error, :timeout}

        {:error, {reason, _server}} ->
          {:error,
           Jido.Error.execution_error("Agent server stopped before the turn replied", %{
             reason: reason
           })}
      end
    end
  end

  def await(%Pending{}, _timeout),
    do: invalid_options("await must run in the process that submitted the turn")

  @doc """
  Discards a pending reply and releases its OTP request monitor. This does not
  cancel the submitted turn. Only the submitting process can abandon a handle.
  Discards an already queued reply too. Do not await this handle again.
  """
  @spec abandon(pending()) :: :ok | {:error, term()}
  def abandon(%Pending{owner: owner, request_id: request_id}) when owner == self() do
    _response = :gen_statem.receive_response(request_id, 0)
    :ok
  end

  def abandon(%Pending{}),
    do: invalid_options("abandon must run in the process that submitted the turn")

  @doc "Returns phase, identity, revision, queue counts, and a bounded active turn view."
  @spec status(:gen_statem.server_ref(), timeout()) :: map()
  def status(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, :status, timeout)
  end

  @doc "Waits for Plugin startup and readiness. Caller timeout does not stop startup."
  def await_ready(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, :await_ready, timeout)
  end

  @doc "Returns terminal summaries in chronological order when debug is enabled."
  @spec history(:gen_statem.server_ref()) :: [map()]
  def history(server), do: :gen_statem.call(server, :history)

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init({agent, opts}) do
    Process.flag(:trap_exit, true)
    Process.set_label({__MODULE__, agent.id})
    runner = Keyword.fetch!(opts, :runner)

    case register_instance(agent.id, opts) do
      {:ok, monitors} -> init_registered(agent, runner, opts, monitors)
      {:error, reason} -> {:stop, reason}
    end
  end

  defp register_instance(id, opts) do
    case opts[:jido] do
      nil ->
        {:ok, %{}}

      jido ->
        registry = Jido.registry_name(jido)
        key = registry_key(id, opts[:partition])

        with :ok <- Jido.AgentServer.RegistrationGuard.claim(jido, key, self()),
             :ok <- register_ready(registry, key) do
          {:ok,
           Map.new(
             [jido, registry, Jido.registration_guard_name(jido)],
             fn name -> {Process.monitor(Process.whereis(name)), name} end
           )}
        end
    end
  catch
    :exit, _ -> {:error, :instance_unavailable}
  end

  defp register_ready(registry, key) do
    case Registry.register(registry, key, :starting) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, pid}} when pid == self() ->
        Registry.update_value(registry, key, fn _ -> :starting end)
        :ok

      error ->
        error
    end
  end

  defp init_registered(agent, runner, opts, monitors) do
    Semantic.point([:jido, :agent_server, :lifecycle, :start], %{agent_id: agent.id})

    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

    data =
      Map.merge(Map.new(@runtime_keys, &{&1, Keyword.fetch!(opts, &1)}), %{
        agent: agent,
        runner: runner,
        jido: opts[:jido],
        partition: opts[:partition],
        instance_monitors: monitors,
        plugin_specs: specs,
        plugin_refs: %{},
        activation: opts[:activation],
        activation_state: opts[:activation_state],
        generation: make_ref(),
        parent: monitor_parent(opts[:activation_state]),
        parent_effect: nil,
        child_monitors: monitor_children(opts[:activation_state]),
        bootstrap: nil,
        ready_waiters: [],
        last_effect_outcome: nil,
        runner_ref: Process.monitor(Process.whereis(runner)),
        state_version: Keyword.get(opts, :state_version, 0),
        active: nil,
        postponed: MapSet.new(),
        queued_from: %{},
        admission_mode: runtime_value(opts[:activation_state], :admission, :open),
        control: nil,
        owners: monitor_owners(opts[:activation_state]),
        idle_timer: nil,
        error_count: 0,
        last_outcome: nil,
        history: :queue.new()
      })

    if data.persistence not in [nil, false] do
      mode = ServerSupervisor.persistence_mode(data.activation_state, data.persistence_mode)
      bootstrap(data, :persistence, data.persistence_timeout, fn -> durable_start(data, mode) end)
    else
      initialize_plugins(data)
    end
  end

  defp initialize_plugins(data) do
    case Jido.Agent.Composition.bind(data.agent) do
      {:ok, agent} ->
        {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

        if data.activation_state,
          do: ServerSupervisor.restore_durable(data.activation_state, agent, data.state_version)

        initialize_bound_plugins(%{data | agent: agent, plugin_specs: specs})

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp initialize_bound_plugins(data) do
    if not Jido.Agent.Topology.empty?(data.agent.topology) or
         TopologyRuntime.buses(data.agent) != [] or
         ServerSupervisor.execution(data.activation_state) != nil or
         Enum.any?(data.plugin_specs, &match?(%{agent_server: %{runtime?: true}}, &1)) do
      owner = self()

      bootstrap(data, :plugins, data.readiness_timeout, fn ->
        runtime = Map.put(data, :owner, owner)

        with :ok <- ServerSupervisor.close_execution(data.activation_state),
             :ok <- CompositionRuntime.validate_runtime(runtime),
             {:ok, refs} <- bootstrap_plugins(data, data.activation, owner),
             {:ok, _} <- CompositionRuntime.reconcile(runtime),
             do: {:ok, refs}
      end)
    else
      mark_ready(data)
      replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))

      {:ok, :idle, arm_idle(%{data | bootstrap: nil, ready_waiters: []}),
       replies ++ [{:next_event, :internal, :control_progress}]}
    end
  end

  defp bootstrap(data, kind, timeout, fun) do
    token = make_ref()
    deadline = System.monotonic_time(:millisecond) + timeout
    timer = Process.send_after(self(), {:readiness_timeout, token}, timeout)
    task = Task.async(fun)
    boot = %{task: task, token: token, timer: timer, deadline: deadline, kind: kind}
    phase = if kind == :persistence, do: :restoring, else: :initializing
    {:ok, phase, %{data | bootstrap: boot}}
  end

  defp durable_options(data), do: [instance: data.jido, partition: data.partition]

  defp durable_start(data, mode) do
    with :ok <- ServerSupervisor.close_execution(data.activation_state),
         {:ok, config} <- Jido.Persistence.resolve_config(data.persistence, data.jido),
         true <- not is_nil(config),
         {:ok, agent, revision} <- durable_load(config, data.agent, mode, durable_options(data)),
         {:ok, agent} <- Jido.Agent.Validation.validate_instance(agent),
         true <- is_integer(revision) and revision >= 0,
         true <- agent.id == data.agent.id,
         true <- agent.module == data.agent.module do
      {:ok, agent, revision, config}
    else
      false -> {:error, :incompatible_durable_checkpoint}
      {:error, _} = error -> error
    end
  end

  defp durable_load(config, agent, :create, opts) do
    with {:ok, agent} <- Jido.Agent.Composition.bind(agent),
         :ok <- Jido.Persistence.create_agent(config, agent, opts),
         do: {:ok, agent, 0}
  end

  defp durable_load(config, agent, :restore, opts),
    do: Jido.Persistence.load_agent_with_revision(config, agent.module, agent.id, opts)

  @doc false
  def bootstrap_current_plugins(data, owner), do: bootstrap_plugins(data, data.activation, owner)

  defp bootstrap_plugins(data, activation, owner) do
    Enum.reduce_while(data.plugin_specs, {:ok, %{}}, fn spec, {:ok, refs} ->
      init = plugin_init(data, spec, owner)

      case Callbacks.child_spec(init, spec) do
        :none ->
          {:cont, {:ok, Map.put(refs, spec.module, nil)}}

        {:ok, child_spec} ->
          case ServerSupervisor.start_plugin(activation, spec, child_spec, data.activation_state) do
            {:ok, pid} ->
              {:cont, {:ok, Map.put(refs, spec.module, pid)}}

            _ ->
              {:halt, {:error, :plugin_start_failed}}
          end

        _ ->
          {:halt, {:error, :invalid_plugin_child_spec}}
      end
    end)
    |> case do
      {:ok, refs} ->
        Enum.reduce_while(data.plugin_specs, {:ok, refs}, fn spec, result ->
          case Callbacks.await_ready(spec, Map.get(refs, spec.module)) do
            :ok -> {:cont, result}
            _ -> {:halt, {:error, :plugin_not_ready}}
          end
        end)

      error ->
        error
    end
  catch
    _, _ -> {:error, :plugin_start_failed}
  end

  defp owned_plugin_state(agent, %{agent: %{state_key: key}}) when not is_nil(key),
    do: Map.get(agent.state, key)

  defp owned_plugin_state(_agent, _spec), do: nil

  defp plugin_init(data, spec, owner) do
    %Jido.Plugin.Init{
      agent_server: owner,
      agent_id: data.agent.id,
      module: spec.module,
      plugin_state: owned_plugin_state(data.agent, spec),
      state_version: data.state_version,
      jido: data.jido,
      partition: data.partition
    }
  end

  defp mark_ready(%{jido: nil}), do: :ok

  defp mark_ready(data) do
    Registry.update_value(
      Jido.registry_name(data.jido),
      registry_key(data.agent.id, data.partition),
      fn _ -> :ready end
    )

    :ok
  end

  @doc """
  Starts a tagged local child Agent. The default `placement: :owned` puts its
  activation under the parent. `:independent` uses the instance supervisor.
  Independent children accept `on_parent_exit: :stop | :continue | :emit_orphan`.
  The last policy requires `orphan_dispatch:`. Parent means activation lifetime,
  not one server PID. A caller timeout does not cancel supervised startup.
  """
  def spawn_child(server, agent, tag, opts \\ [])

  def spawn_child(server, %Agent{} = agent, tag, opts) do
    token = make_ref()

    with {:ok, _agent} <- Jido.Agent.Validation.validate_instance(agent),
         {:ok, context, parent} <- child_options(server, tag, opts, token),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        supervisor =
          case parent.placement do
            :owned ->
              {:ok, supervisor} = ServerSupervisor.child_supervisor(context.activation)
              supervisor

            :independent ->
              Jido.agent_supervisor_name(context.jido)
          end

        opts =
          context.opts
          |> Keyword.merge(Keyword.get(opts, :server_options, []))
          |> Keyword.put(:agent, agent)

        spec = %{
          child_spec(opts)
          | start: {ServerSupervisor, :start_link, [opts, parent]},
            restart: parent.restart
        }

        case start_activation(supervisor, spec) do
          {:ok, worker} ->
            {:ok, worker}

          error ->
            ServerSupervisor.release(context.state, tag, token)
            error
        end
      catch
        :exit, reason ->
          ServerSupervisor.release(context.state, tag, token)
          {:error, {:child_start_failed, reason}}
      end
    end
  end

  def spawn_child(_server, _agent, _tag, _opts),
    do: invalid_options("expected a complete child Agent instance")

  @doc "Returns one committed Agent and revision from the same server event."
  def snapshot(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout), do: :gen_statem.call(server, :snapshot, timeout)
  end

  @doc "Runs a snapshot upgrade Action through the serial commit boundary."
  def upgrade(server, action, opts \\ []) do
    with {:ok, options} <- Jido.Agent.Validation.options(opts, [:context, :timeout]),
         context = Map.get(options, :context, %{}),
         :ok <- Jido.Agent.Data.plain_map(context),
         timeout = Map.get(options, :timeout, 5_000),
         :ok <- validate_wait(timeout) do
      :gen_statem.call(server, {:upgrade, make_ref(), action, context}, timeout)
    end
  end

  @doc "Returns live tagged children with separate worker and activation PIDs."
  def children(server, timeout \\ 5_000) do
    with :ok <- validate_wait(timeout) do
      context = :gen_statem.call(server, :child_context, timeout)
      live_children(context.state)
    end
  end

  defp live_children(nil), do: %{}

  defp live_children(state) do
    Map.new(
      Enum.flat_map(ServerSupervisor.records(state), fn
        {{:child, tag}, %{root: root} = record} ->
          case live_child(root) do
            nil -> []
            worker -> [{tag, %{pid: worker, activation: root, placement: record.placement}}]
          end

        _ ->
          []
      end)
    )
  end

  @doc """
  Stops the complete tagged child activation and confirms its shutdown.
  Removing a permanent entry uses OTP supervisor shutdown.
  """
  def stop_child(server, tag, reason \\ :shutdown) do
    case Map.fetch(children(server), tag) do
      {:ok, %{pid: worker, activation: root, placement: placement}} ->
        context = :gen_statem.call(server, :child_context)
        [{_, record}] = :ets.lookup(context.state, {:child, tag})

        result =
          if Map.get(record, :restart, :transient) == :permanent do
            supervisor =
              case placement do
                :owned ->
                  {:ok, supervisor} = ServerSupervisor.child_supervisor(context.activation)
                  supervisor

                :independent ->
                  Jido.agent_supervisor_name(context.jido)
              end

            DynamicSupervisor.terminate_child(supervisor, root)
          else
            stop(worker, reason)
          end

        with :ok <- result,
             do: :gen_statem.call(server, {:forget_child, tag, root})

      :error ->
        {:error, :child_not_found}
    end
  end

  @doc """
  Attaches an independent orphan to a new logical parent in the same instance
  and partition. Rejects bare workers, unavailable ancestry, and adoption while
  an orphan notification is pending.
  """
  def adopt_child(server, child, tag, opts \\ []) do
    valid? =
      Keyword.keyword?(opts) and
        length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
        Keyword.get(opts, :placement, :independent) == :independent

    if valid? and alive?(child) do
      token = make_ref()
      opts = Keyword.put(opts, :placement, :independent)

      with {:ok, context, parent} <- child_options(server, tag, opts, token) do
        # Adoption changes existing graph edges. Serialize that rare operation
        # within this local instance and partition, including the cycle check.
        lock = {{__MODULE__, :adoption, context.jido, context.partition}, self()}

        case :global.trans(
               lock,
               fn -> attach_child(server, child, tag, token, context, parent) end,
               [node()],
               0
             ) do
          :aborted -> {:error, :adoption_busy}
          result -> result
        end
      end
    else
      {:error, :invalid_child_options}
    end
  end

  defp attach_child(server, child, tag, token, context, parent) do
    with :ok <- validate_adoption(context, child),
         :ok <- :gen_statem.call(server, {:reserve_child, tag, token}) do
      try do
        result = :gen_statem.call(child, {:attach_parent, parent})
        if result != :ok, do: ServerSupervisor.release(context.state, tag, token)
        result
      catch
        :exit, _ ->
          ServerSupervisor.release(context.state, tag, token)
          {:error, :child_unavailable}
      end
    end
  end

  defp validate_adoption(context, child) do
    root = activation(child)

    cond do
      is_nil(root) ->
        {:error, :activation_required}

      root == context.activation ->
        {:error, :self_adoption}

      true ->
        case ancestor?(context.activation, root, []) do
          true -> {:error, :cyclic_parent}
          false -> :ok
          error -> error
        end
    end
  catch
    :exit, _ -> {:error, :child_unavailable}
  end

  @spec ancestor?(pid() | nil, pid(), [pid()]) :: boolean() | {:error, atom()}
  defp ancestor?(nil, _root, _visited), do: false
  defp ancestor?(root, root, _visited), do: true

  defp ancestor?(current, root, visited) do
    if current in visited do
      true
    else
      worker = ServerSupervisor.worker(current)

      case :gen_statem.call(worker, :parent) do
        nil -> false
        parent -> ancestor?(parent.activation, root, [current | visited])
      end
    end
  catch
    :exit, _ -> {:error, :ancestor_unavailable}
  end

  defp live_child(root) do
    if Process.alive?(root), do: ServerSupervisor.worker(root)
  catch
    :exit, _ -> nil
  end

  defp start_activation(supervisor, spec) do
    with {:ok, root} <- DynamicSupervisor.start_child(supervisor, spec) do
      worker = live_child(root)

      if is_pid(worker) and Process.alive?(worker) do
        {:ok, worker}
      else
        DynamicSupervisor.terminate_child(supervisor, root)
        {:error, :worker_unavailable}
      end
    end
  end

  defp child_options(server, tag, opts, token) do
    if Keyword.keyword?(opts) and
         length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) and
         Keyword.keys(opts) --
           [:placement, :on_parent_exit, :orphan_dispatch, :restart, :server_options, :meta] == [] do
      context = :gen_statem.call(server, :child_context)
      placement = Keyword.get(opts, :placement, :owned)
      policy = Keyword.get(opts, :on_parent_exit, :stop)
      dispatch = opts[:orphan_dispatch]

      cond do
        is_nil(context.activation) ->
          {:error, :activation_required}

        Jido.AgentServer.Directive.validate_restart_policy(
          Keyword.get(opts, :restart, :transient)
        ) != :ok ->
          {:error, :invalid_restart_policy}

        not Keyword.keyword?(Keyword.get(opts, :server_options, [])) ->
          {:error, :invalid_child_options}

        not (is_atom(tag) or is_binary(tag)) or is_nil(tag) ->
          {:error, :invalid_child_tag}

        placement not in [:owned, :independent] ->
          {:error, :invalid_placement}

        policy not in [:stop, :continue, :emit_orphan] ->
          {:error, :invalid_parent_policy}

        placement == :owned and policy != :stop ->
          {:error, :owned_child_cannot_survive_parent}

        placement == :independent and is_nil(context.jido) ->
          {:error, :jido_instance_required}

        policy == :emit_orphan and (is_nil(dispatch) or validate_dispatch(dispatch) != :ok) ->
          {:error, :invalid_orphan_dispatch}

        true ->
          {:ok, context,
           %{
             restart: Keyword.get(opts, :restart, :transient),
             meta: Keyword.get(opts, :meta, %{}),
             activation: context.activation,
             state: context.state,
             token: token,
             agent_id: context.agent_id,
             tag: tag,
             placement: placement,
             policy: policy,
             dispatch: dispatch,
             jido: context.jido,
             partition: context.partition
           }}
      end
    else
      {:error, :invalid_child_options}
    end
  end

  @doc "Returns the activation supervisor PID, or nil for a bare worker."
  def activation(server), do: :gen_statem.call(server, :activation)

  defp public_parent(nil), do: nil
  defp public_parent(parent), do: Map.drop(parent, [:monitor, :state, :token, :dispatch])

  defp monitor_parent(nil), do: nil

  defp monitor_parent(state) do
    case ServerSupervisor.parent(state) do
      nil -> nil
      parent -> Map.put(parent, :monitor, Process.monitor(parent.activation))
    end
  end

  defp forget_child_monitors(monitors, tag, token) do
    Enum.reduce(monitors, %{}, fn {ref, value}, acc ->
      case value do
        {_, ^tag, ^token} ->
          Process.demonitor(ref, [:flush])
          acc

        _ ->
          Map.put(acc, ref, value)
      end
    end)
  end

  defp monitor_children(nil), do: %{}

  defp monitor_children(state) do
    Map.new(
      Enum.map(ServerSupervisor.records(state), fn {{:child, tag}, record} ->
        {kind, pid} =
          case record do
            %{root: root} -> {:root, root}
            %{caller: caller} -> {:reservation, caller}
          end

        {Process.monitor(pid), {kind, tag, record.token}}
      end)
    )
  end

  @impl true
  def handle_event({:call, from}, :child_context, _phase, data) do
    context = %{
      activation: data.activation,
      state: data.activation_state,
      agent_id: data.agent.id,
      jido: data.jido,
      partition: data.partition,
      opts:
        Enum.map(@runtime_keys, &{&1, Map.fetch!(data, &1)}) ++
          [runner: data.runner, jido: data.jido, partition: data.partition]
    }

    {:keep_state_and_data, reply(from, context)}
  end

  def handle_event({:call, from}, {:reserve_child, tag, token}, _phase, data) do
    {caller, _} = from
    result = ServerSupervisor.reserve(data.activation_state, tag, token, caller)

    data =
      if result == :ok,
        do: %{
          data
          | child_monitors:
              Map.put(data.child_monitors, Process.monitor(caller), {:reservation, tag, token})
        },
        else: data

    {:keep_state, data, reply(from, result)}
  end

  def handle_event({:call, from}, {:forget_child, tag, root}, _phase, data) do
    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{root: ^root, token: token}}] ->
        ServerSupervisor.release(data.activation_state, tag, token)

      _ ->
        :ok
    end

    {:keep_state_and_data, reply(from, :ok)}
  end

  def handle_event({:call, from}, {:attach_parent, parent}, _phase, data) do
    cond do
      data.parent != nil ->
        {:keep_state_and_data, reply(from, {:error, :already_attached})}

      data.parent_effect != nil ->
        {:keep_state_and_data, reply(from, {:error, :orphan_dispatch_pending})}

      parent.jido != data.jido or parent.partition != data.partition or is_nil(data.jido) ->
        {:keep_state_and_data, reply(from, {:error, :different_instance})}

      data.activation == parent.activation ->
        {:keep_state_and_data, reply(from, {:error, :self_adoption})}

      true ->
        case ServerSupervisor.record_child(parent, data.activation, false) do
          :ok ->
            :ets.insert(data.activation_state, {:parent, parent})
            parent = Map.put(parent, :monitor, Process.monitor(parent.activation))
            {:keep_state, %{data | parent: parent}, reply(from, :ok)}

          error ->
            {:keep_state_and_data, reply(from, error)}
        end
    end
  end

  def handle_event({:call, from}, :parent, _phase, data),
    do: {:keep_state_and_data, reply(from, public_parent(data.parent))}

  def handle_event({:call, from}, :activation, _phase, data),
    do: {:keep_state_and_data, reply(from, data.activation)}

  def handle_event({:call, from}, :stop_target, _phase, data) do
    result =
      if control_caller?(from, data),
        do: {:error, :reentrant_turn},
        else: data.activation

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, {:control, kind, policy, timeout}, phase, data) do
    cond do
      control_caller?(from, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      phase in [:restoring, :initializing] ->
        {:keep_state_and_data, reply(from, {:error, :not_ready})}

      data.control != nil ->
        {:keep_state_and_data, reply(from, {:error, :control_in_progress})}

      data.admission_mode == :blocked ->
        {:keep_state_and_data, reply(from, {:error, :unsafe_resume})}

      kind == :hibernate and data.persistence in [nil, false] ->
        {:keep_state_and_data, reply(from, hibernate_error(:persistence_not_configured, true))}

      true ->
        begin_control(phase, data, kind, from, policy, timeout)
    end
  end

  def handle_event({:call, from}, :resume, phase, data) do
    result =
      cond do
        control_caller?(from, data) -> {:error, :reentrant_turn}
        phase in [:restoring, :initializing] -> {:error, :not_ready}
        data.admission_mode == :blocked -> {:error, :unsafe_resume}
        data.control != nil or not settled?(data) -> {:error, :not_quiescent}
        true -> :ok
      end

    if result == :ok,
      do: {:keep_state, data |> set_admission(:open) |> arm_idle(), reply(from, :ok)},
      else: {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, {kind, owner}, phase, data) when kind in [:attach, :detach] do
    owners =
      case {kind, Map.fetch(data.owners, owner)} do
        {:attach, :error} ->
          Map.put(data.owners, owner, Process.monitor(owner))

        {:detach, {:ok, ref}} ->
          Process.demonitor(ref, [:flush])
          Map.delete(data.owners, owner)

        _ ->
          data.owners
      end

    persist_runtime(data.activation_state, :owners, Map.keys(owners))
    data = cancel_idle(%{data | owners: owners})
    data = if phase == :idle, do: arm_idle(data), else: data
    {:keep_state, data, reply(from, :ok)}
  end

  def handle_event({:call, from}, :touch, phase, data) do
    data = cancel_idle(data)
    data = if phase == :idle, do: arm_idle(data), else: data
    {:keep_state, data, reply(from, :ok)}
  end

  def handle_event(:internal, :control_progress, _phase, data), do: control_progress(data)

  def handle_event(:info, {:control_timeout, token}, _phase, %{control: %{token: token}} = data) do
    control_timeout(data)
  end

  def handle_event(:info, {ref, result}, _phase, %{control: %{task: %{ref: ref}}} = data) do
    complete_task(data.control.task)

    cond do
      System.monotonic_time(:millisecond) >= data.control.deadline ->
        control_failed(data, :indeterminate, false)

      result == :ok ->
        Process.cancel_timer(data.control.timer)
        # The caller installs its monitor before requesting save. Reply only
        # after save; it confirms the activation DOWN before returning success.
        replies = reply(data.control.from, :saved)
        {:stop_and_reply, {:shutdown, :hibernate}, replies, %{data | control: nil}}

      true ->
        reason =
          case result do
            {:error, reason} -> reason
            _ -> :indeterminate
          end

        safe? =
          reason != :conflict and reason != :indeterminate and
            not match?({:indeterminate, _}, reason)

        control_failed(data, reason, safe?)
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        _phase,
        %{control: %{task: %{ref: ref}}} = data
      ),
      do: control_failed(data, :indeterminate, false)

  def handle_event(:info, {:DOWN, ref, :process, owner, _}, phase, data)
      when is_map_key(data.owners, owner) and :erlang.map_get(owner, data.owners) == ref do
    owners = Map.delete(data.owners, owner)
    persist_runtime(data.activation_state, :owners, Map.keys(owners))
    data = cancel_idle(%{data | owners: owners})
    {:keep_state, if(phase == :idle, do: arm_idle(data), else: data)}
  end

  def handle_event(:info, {:idle_timeout, token}, :idle, %{idle_timer: {_, token}} = data) do
    data = %{data | idle_timer: nil}

    if map_size(data.owners) == 0 and data.admission_mode == :open and settled?(data) do
      case data.idle_policy do
        :stop ->
          {:stop, {:shutdown, :idle_timeout}, data}

        :hibernate ->
          begin_control(:idle, data, :hibernate, nil, :finish, data.persistence_timeout)
      end
    else
      :keep_state_and_data
    end
  end

  # A recovery group can restart a Plugin while the worker still loads its
  # durable checkpoint. Do not give that Plugin the supplied initial state.
  def handle_event(
        {:call, _from},
        {kind, _package},
        :restoring,
        %{bootstrap: %{kind: :persistence}}
      )
      when kind in [:plugin_init, :plugin_start],
      do: {:keep_state_and_data, [:postpone]}

  def handle_event({:call, from}, {kind, package}, _phase, data)
      when kind in [:plugin_init, :plugin_start] do
    spec = Enum.find(data.plugin_specs, &(&1.module == package))

    result =
      cond do
        is_nil(spec) -> {:error, :plugin_not_found}
        kind == :plugin_init -> {:ok, plugin_init(data, spec, self())}
        true -> {:ok, plugin_init(data, spec, self()), spec}
      end

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event({:call, from}, :snapshot, phase, _data)
      when phase in [:initializing, :restoring],
      do: {:keep_state_and_data, reply(from, {:error, :not_ready})}

  def handle_event({:call, from}, :snapshot, _phase, data),
    do:
      {:keep_state_and_data, reply(from, %{agent: data.agent, state_version: data.state_version})}

  def handle_event({:call, from}, {:upgrade, token, action, context}, :idle, data) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    if data.admission_mode == :open do
      signal = Signal.new!("jido.agent_server.upgrade", %{}, source: "/agent_server")
      start_turn({:call, from}, signal, context, data, {:upgrade, action})
    else
      reject_turn({:call, from}, {:not_admitting, data.admission_mode}, data)
    end
  end

  def handle_event({:call, from}, {:upgrade, token, _action, _context}, _phase, data) do
    if reentrant?({:call, from}, data) or bootstrap_caller?(from, data),
      do: reject_turn({:call, from}, :reentrant_turn, data),
      else: postpone_turn({:call, from}, token, data)
  end

  def handle_event(:cast, {kind, _source, _signal}, phase, data)
      when kind in [:topology_output, :topology_bus] and
             (phase in [:initializing, :restoring] or
                (phase == :effects and is_map(data.active) and
                   :erlang.is_map_key(:reconciling, data.active) and
                   :erlang.map_get(:reconciling, data.active) == true)),
      do: {:keep_state_and_data, [:postpone]}

  def handle_event(:cast, {:topology_output, tag, signal}, _phase, data) do
    case TopologyRuntime.member_output(Map.put(data, :server, self()), tag, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:stop, {:shutdown, {:topology_delivery_failed, reason}}, data}
    end
  end

  def handle_event(:cast, {:topology_bus, name, signal}, _phase, data) do
    case TopologyRuntime.output(Map.put(data, :server, self()), %{kind: :bus, name: name}, signal) do
      :ok -> :keep_state_and_data
      {:error, reason} -> {:stop, {:shutdown, {:topology_delivery_failed, reason}}, data}
    end
  end

  def handle_event({:call, from}, :agent, _phase, data),
    do: {:keep_state_and_data, [{:reply, from, data.agent}]}

  def handle_event({:call, from}, :await_ready, phase, data)
      when phase in [:restoring, :initializing] do
    {caller, _} = from

    if owned_process?(caller, data.bootstrap.task.pid, [], 0) do
      {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}
    else
      {:keep_state, %{data | ready_waiters: [from | data.ready_waiters]}}
    end
  end

  def handle_event({:call, from}, :await_ready, :effects, %{active: %{reconciling: true}} = data) do
    if reentrant?({:call, from}, data),
      do: {:keep_state_and_data, reply(from, {:error, :reentrant_turn})},
      else: {:keep_state, %{data | ready_waiters: [from | data.ready_waiters]}}
  end

  def handle_event({:call, from}, :await_ready, _phase, _data),
    do: {:keep_state_and_data, reply(from, :ok)}

  def handle_event({:call, from}, {:plugin_state, package}, _phase, data) do
    result =
      case Enum.find(data.plugin_specs, &(&1.module == package)) do
        nil -> {:error, :plugin_not_found}
        spec -> {:ok, owned_plugin_state(data.agent, spec)}
      end

    {:keep_state_and_data, reply(from, result)}
  end

  def handle_event(type, {:turn, _token, _signal, _context, _deadline}, phase, data)
      when phase in [:restoring, :initializing],
      do: reject_turn(type, :not_ready, data)

  def handle_event({:call, from}, {:cancel, _id}, phase, _data)
      when phase in [:restoring, :initializing],
      do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event(:info, {ref, result}, phase, %{bootstrap: %{task: %{ref: ref}}} = data)
      when phase in [:restoring, :initializing] do
    complete_task(data.bootstrap.task)
    Process.cancel_timer(data.bootstrap.timer)

    if System.monotonic_time(:millisecond) >= data.bootstrap.deadline do
      {:stop, {:shutdown, bootstrap_timeout(data)}, data}
    else
      finish_bootstrap(result, data)
    end
  end

  def handle_event(
        :info,
        {:readiness_timeout, token},
        phase,
        %{bootstrap: %{token: token}} = data
      )
      when phase in [:restoring, :initializing],
      do: {:stop, {:shutdown, bootstrap_timeout(data)}, data}

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, _reason},
        phase,
        %{bootstrap: %{task: %{ref: ref}}} = data
      )
      when phase in [:restoring, :initializing],
      do: {:stop, {:shutdown, :plugin_start_failed}, data}

  def handle_event({:call, from}, :history, _phase, data),
    do: {:keep_state_and_data, reply(from, :queue.to_list(data.history))}

  def handle_event({:call, from}, :status, phase, data) do
    {:message_queue_len, mailbox} = Process.info(self(), :message_queue_len)

    status = %{
      phase:
        case phase do
          phase when phase in [:restoring, :initializing] -> :initializing
          :idle -> :idle
          _ -> :running
        end,
      ready?:
        phase not in [:restoring, :initializing] and not match?(%{reconciling: true}, data.active),
      plugin_count: length(data.plugin_specs),
      activation: data.activation,
      generation: data.generation,
      parent: public_parent(data.parent),
      agent_id: data.agent.id,
      jido: data.jido,
      partition: data.partition,
      effects: effect_status(data.active),
      last_effect_outcome: data.last_effect_outcome,
      state_version: data.state_version,
      error_count: data.error_count,
      last_outcome: data.last_outcome,
      owners: Map.keys(data.owners),
      idle_timeout: data.idle_timeout,
      idle_policy: data.idle_policy,
      admission: %{
        mode: data.admission_mode,
        postponed: MapSet.size(data.postponed),
        limit: data.max_postponed_signals,
        message_queue_len: mailbox
      },
      active: active_status(data.active, phase)
    }

    {:keep_state_and_data, [{:reply, from, status}]}
  end

  def handle_event({:call, from}, {:cancel, _id}, :idle, _data),
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event({:call, from}, {:cancel, _id}, :saving, _data),
    do: {:keep_state_and_data, reply(from, {:error, :commit_in_progress})}

  def handle_event({:call, from}, {:cancel, _id}, phase, _data) when phase in [:policy, :effects],
    do: {:keep_state_and_data, reply(from, {:error, :not_running})}

  def handle_event(:info, {:turn_timeout, _id}, phase, _data)
      when phase in [:saving, :policy, :effects],
      do: :keep_state_and_data

  def handle_event(:info, {:persistence_timeout, id}, :saving, %{active: %{turn_id: id}} = data),
    do: stop_durable(data, :indeterminate)

  def handle_event(
        :info,
        {:composition_timeout, id},
        :effects,
        %{active: %{turn_id: id, reconciling: true}} = data
      ),
      do:
        stop_failed(
          data,
          execution_error("Composition readiness timed out", :composition_timeout),
          :effects
        )

  def handle_event(:internal, :effect_next, :effects, data), do: next_effect(data)

  def handle_event(
        :info,
        {:commit_timeout, id},
        :effects,
        %{active: %{turn_id: id, commit_hooks: [_ | _]}} = data
      ) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    finish_effects(put_in(data.active.operation, nil), :timed_out)
  end

  def handle_event(
        :info,
        {:effect_timeout, id},
        :effects,
        %{active: %{turn_id: id, commit_hooks: []}} = data
      ) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    finish_effects(put_in(data.active.operation, nil), :timed_out)
  end

  def handle_event(:info, {:policy_timeout, id}, :policy, %{active: %{turn_id: id}} = data) do
    Task.shutdown(data.active.operation.task, :brutal_kill)
    complete_terminal(put_in(data.active.operation, nil), {:stop, :error_policy_timeout})
  end

  def handle_event({:call, from} = type, {:cancel, id}, phase, data) do
    cond do
      id != :active and id != data.active.turn_id ->
        {:keep_state_and_data, reply(from, {:error, :stale_turn})}

      reentrant?(type, data) ->
        {:keep_state_and_data, reply(from, {:error, :reentrant_turn})}

      true ->
        data = update_in(data.active.cancel_waiters, &[from | &1])
        abort_turn(phase, data, :cancelled)
    end
  end

  def handle_event(:info, {:turn_timeout, id}, phase, %{active: %{turn_id: id}} = data),
    do: abort_turn(phase, data, :turn_timeout)

  def handle_event(type, {:turn, token, _signal, _context, _deadline}, _phase, data)
      when data.admission_mode != :open do
    queued? = MapSet.member?(data.postponed, token)
    data = %{data | postponed: MapSet.delete(data.postponed, token)}
    replies = if queued?, do: [], else: turn_rejection(type, :quiesced, data)
    {:keep_state, data, replies ++ [{:next_event, :internal, :control_progress}]}
  end

  def handle_event(type, {:turn, token, signal, context, deadline}, :idle, data)
      when type == :cast or (is_tuple(type) and elem(type, 0) == :call) do
    data = %{
      data
      | postponed: MapSet.delete(data.postponed, token),
        queued_from: Map.delete(data.queued_from, token)
    }

    case admission_status(deadline) do
      :ok -> start_turn(type, signal, context, data)
      {:error, reason} -> reject_turn(type, reason, data)
    end
  end

  def handle_event(type, {:turn, token, _signal, _context, deadline}, phase, data)
      when phase in [
             :preparing,
             :starting,
             :running,
             :settling,
             :cleaning,
             :reconfiguring,
             :saving,
             :policy,
             :effects
           ] and
             (type == :cast or (is_tuple(type) and elem(type, 0) == :call)) do
    admission =
      if reentrant?(type, data), do: {:error, :reentrant_turn}, else: admission_status(deadline)

    case admission do
      {:error, reason} ->
        reject_turn(type, reason, %{
          data
          | postponed: MapSet.delete(data.postponed, token),
            queued_from: Map.delete(data.queued_from, token)
        })

      :ok ->
        postpone_turn(type, token, data)
    end
  end

  def handle_event(
        :info,
        {ref, result},
        phase,
        %{active: %{operation: %{task: %{ref: ref}} = operation}} = data
      ) do
    complete_task(operation.task)
    data = put_in(data.active.operation, nil)

    if phase not in [:cleaning, :saving, :policy, :effects] and expired?(data.active) do
      abort_turn(phase, data, :turn_timeout)
    else
      operation_result(operation.kind, result, data)
    end
  end

  def handle_event(:info, {:worker_complete, id}, :starting, %{active: %{turn_id: id}}),
    do: {:keep_state_and_data, [:postpone]}

  def handle_event(:info, {:worker_complete, id}, :running, %{active: %{turn_id: id}} = data) do
    active = data.active
    runner = data.runner

    config =
      Map.take(data, [
        :directive_handler,
        :max_directives_per_turn,
        :default_dispatch,
        :jido,
        :plugin_specs,
        :plugin_refs,
        :agent,
        :activation,
        :activation_state,
        :parent,
        :runner,
        :partition
      ])

    operation(:settle, data, fn -> settle_worker(runner, active, config) end)
  end

  def handle_event(:info, {:DOWN, ref, :process, _pid, _reason}, phase, data)
      when is_map_key(data.instance_monitors, ref),
      do: stop_failed(data, execution_error("Instance ownership stopped", :instance_lost), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{runner_ref: ref} = data
      ),
      do: stop_failed(data, execution_error("Runic Runner stopped", reason), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{active: %{operation: %{task: %{ref: ref}}}} = data
      ),
      do: stop_failed(data, execution_error("Turn lifecycle task stopped", reason), phase)

  # Cleanup cancels the Worker. Its DOWN can arrive before the task result.
  def handle_event(:info, {:DOWN, ref, :process, _pid, _reason}, :cleaning, %{
        active: %{worker_ref: ref}
      }),
      do: :keep_state_and_data

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        phase,
        %{active: %{worker_ref: ref}} = data
      ),
      do: stop_failed(data, execution_error("Owned Runic Worker stopped", reason), phase)

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        _phase,
        %{parent: %{monitor: ref}} = data
      ) do
    parent = data.parent
    :ets.insert(data.activation_state, {:parent, nil})
    data = %{data | parent: nil}

    case parent.policy do
      :stop ->
        {:stop, {:shutdown, :parent_down}, data}

      :continue ->
        {:keep_state, data}

      :emit_orphan ->
        signal =
          Signal.new!(
            "jido.agent_server.orphaned",
            %{parent_id: parent.agent_id, tag: parent.tag, reason: inspect(reason)},
            source: "/agent/" <> data.agent.id
          )

        dispatch = DispatchPreparation.inherit_bus_scope(parent.dispatch, data.jido)
        task = Task.async(fn -> Jido.Signal.Dispatch.dispatch(signal, dispatch) end)
        timer = Process.send_after(self(), {:orphan_timeout, task.ref}, data.directive_timeout)

        {:keep_state,
         %{
           data
           | parent_effect: %{
               task: task,
               timer: timer,
               deadline: System.monotonic_time(:millisecond) + data.directive_timeout
             }
         }}
    end
  end

  def handle_event(:info, {ref, result}, _phase, %{parent_effect: %{task: %{ref: ref}}} = data) do
    complete_task(data.parent_effect.task)
    Process.cancel_timer(data.parent_effect.timer)
    expired = System.monotonic_time(:millisecond) >= data.parent_effect.deadline
    data = %{data | parent_effect: nil}

    if result == :ok and not expired,
      do: {:keep_state, data, [{:next_event, :internal, :control_progress}]},
      else: {:stop, {:shutdown, :orphan_dispatch_failed}, data}
  end

  def handle_event(
        :info,
        {:orphan_timeout, ref},
        _phase,
        %{parent_effect: %{task: %{ref: ref}}} = data
      ),
      do: {:stop, {:shutdown, :orphan_dispatch_timeout}, data}

  def handle_event(
        :info,
        {:DOWN, ref, :process, _, _},
        _phase,
        %{parent_effect: %{task: %{ref: ref}}} = data
      ),
      do: {:stop, {:shutdown, :orphan_dispatch_failed}, data}

  def handle_event(:info, {:child_registered, tag, token, root}, _phase, data) do
    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{token: ^token, root: ^root}}] ->
        monitors = forget_child_monitors(data.child_monitors, tag, token)
        monitors = Map.put(monitors, Process.monitor(root), {:root, tag, token})
        {:keep_state, %{data | child_monitors: monitors}}

      _ ->
        :keep_state_and_data
    end
  end

  def handle_event(:info, {:child_released, tag, token}, _phase, data),
    do:
      {:keep_state,
       %{data | child_monitors: forget_child_monitors(data.child_monitors, tag, token)}}

  def handle_event(:info, {:DOWN, ref, :process, pid, reason}, _phase, data)
      when is_map_key(data.child_monitors, ref) do
    {{kind, tag, token}, monitors} = Map.pop(data.child_monitors, ref)

    case :ets.lookup(data.activation_state, {:child, tag}) do
      [{_, %{root: _root}}] when kind == :reservation ->
        :ok

      [{_, %{token: ^token, caller: ^pid} = record}] when kind == :reservation ->
        :ets.delete_object(data.activation_state, {{:child, tag}, record})

      [{_, %{token: ^token, root: ^pid} = record}] ->
        if record.restart? == false or
             (Map.get(record, :restart, :transient) != :permanent and
                (reason in [:normal, :shutdown] or match?({:shutdown, _}, reason))),
           do: :ets.delete_object(data.activation_state, {{:child, tag}, record})

      _ ->
        :ok
    end

    {:keep_state, %{data | child_monitors: monitors}}
  end

  def handle_event(:info, _message, _phase, _data), do: :keep_state_and_data

  defp bootstrap_timeout(%{bootstrap: %{kind: :persistence}}), do: :persistence_timeout
  defp bootstrap_timeout(_data), do: :readiness_timeout

  defp finish_bootstrap(
         {:ok, agent, revision, config},
         %{bootstrap: %{kind: :persistence}} = data
       ) do
    ServerSupervisor.restore_durable(data.activation_state, agent, revision)
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(agent))

    data = %{
      data
      | agent: agent,
        plugin_specs: specs,
        state_version: revision,
        persistence: config,
        bootstrap: nil
    }

    case initialize_plugins(data) do
      {:ok, phase, next} -> {:next_state, phase, next}
      {:ok, phase, next, actions} -> {:next_state, phase, next, actions}
    end
  end

  defp finish_bootstrap({:ok, refs}, %{bootstrap: %{kind: :plugins}} = data) do
    mark_ready(data)
    replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))
    idle_transition(%{data | bootstrap: nil, plugin_refs: refs, ready_waiters: []}, replies)
  end

  defp finish_bootstrap({:error, reason}, data),
    do: {:stop, {:shutdown, reason}, data}

  @impl true
  def terminate(_reason, phase, data) do
    cancel_idle(data)

    if data.control do
      Process.cancel_timer(data.control.timer)
      if data.control.task, do: Task.shutdown(data.control.task, :brutal_kill)
    end

    if data.parent_effect do
      Process.cancel_timer(data.parent_effect.timer)
      Task.shutdown(data.parent_effect.task, :brutal_kill)
    end

    if data.bootstrap do
      Process.cancel_timer(data.bootstrap.timer)
      Task.shutdown(data.bootstrap.task, :brutal_kill)
    end

    if data.active do
      if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)

      if phase == :effects and is_nil(data.active.effect_outcome),
        do: record_effects(data, :indeterminate)

      unless data.active.outcome do
        record_outcome(data, :indeterminate, phase, false, 0)
      end

      # Runic also stops owned execution after abrupt owner death.
      try do
        Runner.cancel(data.runner, data.active.turn_id)
      catch
        :exit, _ -> :ok
      end
    end

    TraceContext.clear()
    Semantic.point([:jido, :agent_server, :lifecycle, :stop], %{agent_id: data.agent.id})
    :ok
  end

  defp start_turn(type, signal, context, data, mode \\ :turn) do
    data = cancel_idle(data)

    from =
      case type do
        {:call, from} -> from
        :cast -> nil
      end

    turn_id = Jido.Signal.ID.generate!()
    agent = data.agent
    trace = TraceContext.begin_turn(signal)

    span =
      Semantic.start(
        [:jido, :agent_server, :turn],
        Map.merge(trace, %{agent_id: agent.id, turn_id: turn_id, signal_id: signal.id})
      )

    TraceContext.put(span.trace)
    context = context |> Map.put(:turn_id, turn_id) |> Map.put(:trace_context, span.trace)

    active = %{
      from: from,
      span: span,
      signal_type: signal.type,
      outcome: nil,
      effects: [],
      effect_index: 0,
      effect_timer: nil,
      effect_deadline: nil,
      effect_outcome: nil,
      failure_stage: nil,
      policy_timer: nil,
      policy_deadline: nil,
      turn_id: turn_id,
      signal_id: signal.id,
      source_signal: signal,
      turn_context: Map.drop(context, [:turn_id, :trace_context]),
      commit_hooks: [],
      start_version: data.state_version,
      prepared: nil,
      operation: nil,
      worker: nil,
      worker_ref: nil,
      execution_id: nil,
      result: nil,
      abort_reason: nil,
      cancel_waiters: [],
      deadline:
        if(data.turn_timeout == :infinity,
          do: :infinity,
          else: System.monotonic_time(:millisecond) + data.turn_timeout
        ),
      timer:
        if(data.turn_timeout == :infinity,
          do: nil,
          else: Process.send_after(self(), {:turn_timeout, turn_id}, data.turn_timeout)
        )
    }

    case mode do
      :turn ->
        operation(:prepare, %{data | active: active}, fn ->
          prepare_turn(agent, signal, context, data)
        end)

      {:upgrade, action} ->
        operation(:upgrade, %{data | active: active}, fn ->
          with {:ok, snapshot} <- Jido.Persistence.snapshot(agent, context: context),
               {:ok, candidate} <- Jido.Persistence.upgrade(snapshot, action, context: context),
               {:ok, candidate} <- Jido.Agent.Composition.bind(candidate),
               :ok <- CompositionRuntime.check(data, candidate, []) do
            {:ok, candidate, []}
          end
        end)
    end
  end

  defp prepare_turn(agent, signal, context, data) do
    with {:ok, inputs} <- Jido.Agent.Plugin.prepare(agent, signal, data.plugin_specs),
         {:ok, command} <- Command.new_trusted_agent(agent, signal, context),
         command = %{command | plugin_inputs: inputs},
         {:ok, admitted} <-
           Callbacks.admit(
             command,
             Callbacks.admission_specs(data.plugin_specs),
             data.plugin_refs,
             data.state_version
           ),
         {:ok, prepared} <-
           AgentRunner.prepare_for_server(admitted, signal, [], data.plugin_specs) do
      {:ok, prepared}
    else
      {:error, _stage, reason} -> {:error, reason}
      {:error, _} = error -> error
    end
  end

  defp operation(kind, data, fun) do
    captured = TraceContext.capture()
    task = Task.async(fn -> TraceContext.with_context(captured, fun) end)

    phases = %{
      upgrade: :preparing,
      prepare: :preparing,
      start: :starting,
      execute: :starting,
      settle: :settling,
      cleanup: :cleaning,
      reconfigure: :reconfiguring,
      resume_plugins: :cleaning,
      reconcile: :effects,
      save: :saving,
      policy: :policy,
      commit_hook: :effects,
      effect: :effects
    }

    {:next_state, Map.fetch!(phases, kind),
     put_in(data.active.operation, %{kind: kind, task: task})}
  end

  defp operation_result(:upgrade, result, data), do: finish(data, result)

  defp operation_result(:prepare, {:ok, prepared}, data) do
    data = put_in(data.active.prepared, prepared)
    owner = self()
    runner = data.runner
    id = data.active.turn_id
    exec_opts = data.exec_opts
    operation(:start, data, fn -> start_worker(runner, id, owner, prepared, exec_opts) end)
  end

  defp operation_result(:start, {:ok, worker, input, context}, data) do
    # Publish ownership before execution can call back into this server.
    active = %{data.active | worker: worker, worker_ref: Process.monitor(worker)}
    runner = data.runner
    id = active.turn_id
    policy = execution_policy(data.exec_opts)

    case ServerSupervisor.remember_execution(data.activation_state, runner, id, worker) do
      :ok ->
        operation(:execute, %{data | active: active}, fn ->
          Runner.start_execution(runner, id, Jido.Exec.Fact.local_value(input),
            run_context: %{_global: context},
            scheduler_policies: [{:default, policy}]
          )
        end)

      error ->
        operation_result(:start, error, %{data | active: active})
    end
  end

  defp operation_result(:execute, {:ok, execution_id}, data),
    do: {:next_state, :running, put_in(data.active.execution_id, execution_id)}

  defp operation_result(:cleanup, :ok, data) do
    ServerSupervisor.forget_execution(data.activation_state)
    if data.active.worker_ref, do: Process.demonitor(data.active.worker_ref, [:flush])
    data = data |> put_in([:active, :worker], nil) |> put_in([:active, :worker_ref], nil)

    cond do
      data.active.abort_reason -> finish(data, {:error, data.active.abort_reason})
      expired?(data.active) -> finish(data, {:error, :turn_timeout})
      true -> finish(data, data.active.result)
    end
  end

  defp operation_result(:cleanup, {:error, reason}, data),
    do:
      stop_failed(
        data,
        execution_error("Worker cleanup could not be confirmed", reason),
        :cleaning
      )

  defp operation_result(:save, result, data) do
    {timer, deadline} = data.active.storage
    Process.cancel_timer(timer)

    cond do
      System.monotonic_time(:millisecond) >= deadline -> stop_durable(data, :indeterminate)
      result == :ok -> publish_commit(data, data.active.result)
      match?({:error, _}, result) -> stop_durable(data, elem(result, 1))
      true -> stop_durable(data, :indeterminate)
    end
  end

  defp operation_result(:reconfigure, :ok, data), do: finish(data, data.active.result)
  defp operation_result(:reconfigure, {:error, reason}, data), do: finish(data, {:error, reason})

  defp operation_result(:resume_plugins, :ok, data) do
    data = put_in(data.active.paused_plugins, [])
    finish_result(data, data.active.result)
  end

  defp operation_result(:resume_plugins, _, data),
    do:
      stop_failed(data, execution_error("Plugin resume failed", :plugin_resume_failed), :cleaning)

  defp operation_result(:reconcile, {:ok, refs, _members}, data) do
    Process.cancel_timer(data.active.effect_timer)
    replies = Enum.flat_map(data.ready_waiters, &reply(&1, :ok))
    data = %{data | plugin_refs: refs, ready_waiters: []}
    data = put_in(data.active.reconciling, false)
    data = put_in(data.active.paused_plugins, [])

    case begin_effects(data, data.active.effects) do
      {:next_state, phase, next, actions} -> {:next_state, phase, next, replies ++ actions}
    end
  end

  defp operation_result(:reconcile, _, data),
    do:
      stop_failed(
        data,
        execution_error("Committed composition is not ready", :composition_not_ready),
        :effects
      )

  defp operation_result(:policy, decision, data) do
    if System.monotonic_time(:millisecond) >= data.active.policy_deadline,
      do: complete_terminal(data, {:stop, :error_policy_timeout}),
      else: complete_terminal(data, decision)
  end

  defp operation_result(:commit_hook, result, data) do
    cond do
      System.monotonic_time(:millisecond) >= data.active.effect_deadline ->
        finish_effects(data, :timed_out)

      result != :ok ->
        finish_effects(data, :failed)

      true ->
        data = update_in(data.active.commit_hooks, &tl/1)

        data =
          if data.active.commit_hooks == [] do
            Process.cancel_timer(data.active.effect_timer)

            %{
              data
              | active: %{
                  data.active
                  | effect_deadline: System.monotonic_time(:millisecond) + data.directive_timeout,
                    effect_timer:
                      Process.send_after(
                        self(),
                        {:effect_timeout, data.active.turn_id},
                        data.directive_timeout
                      )
                }
            }
          else
            data
          end

        next_effect(data)
    end
  end

  defp operation_result(:effect, result, data) do
    cond do
      System.monotonic_time(:millisecond) >= data.active.effect_deadline ->
        finish_effects(data, :timed_out)

      match?({:stop, _}, result) ->
        Process.cancel_timer(data.active.effect_timer)

        data =
          data |> update_in([:active, :effect_index], &(&1 + 1)) |> record_effects(:succeeded)

        {:stop, normalize_stop_reason(elem(result, 1)), data}

      match?({:reported_error, _}, result) ->
        Process.cancel_timer(data.active.effect_timer)
        data = record_effects(data, :failed)
        data = %{data | error_count: data.error_count + 1}
        apply_failure_policy(put_in(data.active.result, {:error, elem(result, 1)}))

      result == :ok ->
        next_effect(update_in(data.active.effect_index, &(&1 + 1)))

      true ->
        finish_effects(data, :failed)
    end
  end

  defp operation_result(:settle, {:error, stage, reason}, data),
    do: cleanup(put_in(data.active.failure_stage, stage), {:error, reason})

  defp operation_result(:settle, result, data), do: cleanup(data, result)

  defp operation_result(kind, {:error, reason}, data),
    do:
      cleanup(
        put_in(data.active.failure_stage, if(kind == :prepare, do: :preparing, else: :starting)),
        {:error, reason}
      )

  defp expired?(%{deadline: :infinity}), do: false
  defp expired?(active), do: System.monotonic_time(:millisecond) >= active.deadline

  defp abort_turn(:cleaning, data, reason) do
    data =
      if data.active.abort_reason, do: data, else: put_in(data.active.failure_stage, :cleaning)

    {:keep_state, put_in(data.active.abort_reason, data.active.abort_reason || reason)}
  end

  defp abort_turn(phase, data, reason) do
    # Stop the lifecycle task before checking for a Worker. A startup request
    # may already be in the local Worker supervisor mailbox.
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    data = put_in(data.active.operation, nil)
    data = put_in(data.active.failure_stage, phase)
    cleanup(put_in(data.active.abort_reason, reason), nil)
  end

  defp cleanup(data, result) do
    runner = data.runner
    id = data.active.turn_id
    worker = data.active.worker

    operation(:cleanup, put_in(data.active.result, result), fn ->
      # This local supervisor barrier waits for any start_child request sent
      # by the stopped startup task. No new startup task can follow it.
      DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor))

      case Runner.lookup(runner, id) do
        nil when is_nil(worker) -> :ok
        nil -> {:error, :worker_lost_before_cleanup}
        _worker -> Runner.cancel(runner, id)
      end
    end)
  end

  defp start_worker(runner, id, owner, prepared, exec_opts) do
    with {:ok, instruction} <-
           Jido.Instruction.resolve(
             prepared.turn.executable,
             prepared.turn.input,
             prepared.context
           ),
         {:ok, input} <- execution_input(instruction),
         {:ok, workflow} <- Jido.Exec.compile(%{instruction | context: %{}}),
         {:ok, worker} <-
           Runner.start_workflow(runner, id, workflow,
             owner: owner,
             max_concurrency: Keyword.get(exec_opts, :max_concurrency, 1),
             checkpoint_strategy: :manual,
             runnable_order: &execution_order/1,
             hooks: execution_hooks(Keyword.get(exec_opts, :hooks, []), TraceContext.get()),
             on_complete: fn ^id, _workflow -> send(owner, {:worker_complete, id}) end
           ) do
      {:ok, worker, input, instruction.context}
    end
  end

  defp execution_policy(opts) do
    %{
      timeout_ms: Keyword.get(opts, :timeout, :infinity),
      max_retries: Keyword.get(opts, :max_attempts, 1) - 1,
      backoff: Keyword.get(opts, :backoff, :none),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, 500),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, 30_000),
      on_failure: :halt,
      retry_if: {Jido.Action.Error, :retryable?, []}
    }
  end

  defp execution_hooks(hooks, trace) do
    hooks = Enum.map(hooks, fn {name, fun} -> {name, safe_hook(name, fun)} end)
    dispatch = Keyword.get(hooks, :on_dispatch)
    failed = Keyword.get(hooks, :on_failed)

    hooks
    |> Keyword.put(:on_dispatch, fn runnable, state ->
      # Runic carries Logger metadata into its owned native Tasks.
      Logger.metadata(Map.to_list(trace || %{}))
      TraceContext.put(trace)
      if dispatch, do: dispatch.(runnable, state)
    end)
    |> Keyword.put(:on_failed, fn runnable, error, state ->
      try do
        if failed, do: failed.(runnable, error, state)
      after
        # Runic warns with raw values after this hook. Keep ID-only server logs.
        Logger.put_process_level(self(), :error)
      end
    end)
  end

  # Worker hooks are synchronous. They must be short and must not block.
  # Keep Runic's hook error reporter from inspecting application exceptions.
  defp safe_hook(:transform_runnables, fun),
    do: fn runnables, state -> invoke_hook(fun, [runnables, state], runnables) end

  defp safe_hook(name, fun) when name in [:on_dispatch],
    do: fn runnable, state -> invoke_hook(fun, [runnable, state], :ok) end

  defp safe_hook(:on_idle, fun), do: fn state -> invoke_hook(fun, [state], :ok) end

  defp safe_hook(_name, fun),
    do: fn first, second, state -> invoke_hook(fun, [first, second, state], :ok) end

  defp invoke_hook(fun, args, fallback) do
    apply(fun, args)
  catch
    _, _ ->
      Logger.warning("AgentServer execution hook failed")
      fallback
  end

  defp execution_input(%Jido.Instruction{kind: :action}), do: {:ok, %{}}

  defp execution_input(%Jido.Instruction{kind: :flow} = instruction) do
    with {:ok, params} <-
           Jido.Exec.Validation.input(instruction.target, instruction.params, %{
             phase: :flow_input
           }),
         do: {:ok, Jido.Exec.Frame.new(params)}
  end

  defp execution_order(runnable) do
    index =
      case Jido.Exec.Fact.value(runnable.input_fact) do
        {:jido_map_item, index, _id, _params} -> index
        _value -> 0
      end

    {elem(Runic.Workflow.Runnable.order_key(runnable), 0), Map.get(runnable.node, :name), index,
     Runic.Workflow.Runnable.activation_id(runnable)}
  end

  defp settle_worker(runner, active, config) do
    result =
      with {:ok, observation} <- Runner.execution(runner, active.turn_id, active.execution_id),
           {:ok, workflow} <- Runner.get_workflow(runner, active.turn_id),
           do: Jido.Exec.result(workflow, observation)

    case AgentRunner.finish_for_server(active.prepared, result) do
      {:error, _stage, reason} ->
        {:error, if(match?({:error, _}, result), do: :running, else: :settling), reason}

      {:ok, candidate, directives} ->
        with {:ok, candidate} <- Jido.Agent.Composition.bind(candidate),
             :ok <- CompositionRuntime.check(config, candidate, directives),
             :ok <- validate_batch(directives, %{config | agent: candidate}) do
          {:ok, candidate, directives}
        else
          {:error, reason} -> {:error, :directives, reason}
        end
    end
  end

  defp execution_error(message, reason),
    do: Jido.Error.execution_error(message, %{reason: reason})

  defp stop_policy(data) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    complete_terminal(data, {:stop, :error_policy_failed})
  end

  defp stop_failed(data, _error, :effects) do
    if data.active.operation, do: Task.shutdown(data.active.operation.task, :brutal_kill)
    data = record_effects(data, :indeterminate)
    {:stop, {:shutdown, :effect_lifecycle_failed}, %{data | active: nil}}
  end

  defp stop_failed(%{active: %{outcome: outcome}} = data, _error, :policy)
       when not is_nil(outcome),
       do: stop_policy(data)

  defp stop_failed(data, error, phase) do
    data =
      if data.active && is_nil(data.active.outcome),
        do: record_outcome(data, :indeterminate, phase, false, 0),
        else: data

    replies =
      if data.active,
        do:
          reply(data.active.from, {:error, error}) ++ cancel_replies(data.active, {:error, error}),
        else: []

    {:stop_and_reply, {:shutdown, :execution_lifecycle_failed}, replies, data}
  end

  defp postpone_turn(type, token, data) do
    count = MapSet.size(data.postponed)

    cond do
      MapSet.member?(data.postponed, token) ->
        {:keep_state_and_data, [:postpone]}

      data.max_postponed_signals != :infinity and count >= data.max_postponed_signals ->
        reject_turn(
          type,
          {:overloaded, %{limit: data.max_postponed_signals, postponed: count}},
          data
        )

      true ->
        next = %{
          data
          | postponed: MapSet.put(data.postponed, token),
            queued_from: Map.put(data.queued_from, token, type)
        }

        {:keep_state, next, [:postpone]}
    end
  end

  defp reject_turn(type, reason, data),
    do: {:keep_state, data, turn_rejection(type, reason, data)}

  defp turn_rejection(:cast, reason, data) do
    Logger.warning("AgentServer cast dropped", agent_id: data.agent.id, reason: reason)
    []
  end

  defp turn_rejection({:call, from}, reason, _data), do: reply(from, {:error, reason})

  defp bootstrap_caller?(_from, %{bootstrap: nil}), do: false

  defp bootstrap_caller?({caller, _}, data),
    do: owned_process?(caller, data.bootstrap.task.pid, [], 0)

  defp reentrant?(:cast, _data), do: false
  defp reentrant?(_type, %{active: nil}), do: false

  defp reentrant?({:call, {caller, _tag}}, data),
    do:
      Enum.any?(
        [data.active.worker, operation_pid(data.active.operation)],
        fn root -> is_pid(root) and owned_process?(caller, root, [], 0) end
      )

  defp operation_pid(nil), do: nil
  defp operation_pid(operation), do: operation.task.pid

  @spec owned_process?(pid(), pid(), [pid()], non_neg_integer()) :: boolean()
  defp owned_process?(pid, root, _visited, _depth) when pid == root, do: true
  defp owned_process?(pid, _root, _visited, _depth) when pid == self(), do: false

  defp owned_process?(pid, _root, _visited, depth) when node(pid) != node() or depth >= 8,
    do: false

  defp owned_process?(pid, root, visited, depth) do
    if pid in visited do
      false
    else
      visited = [pid | visited]

      callers =
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} -> Keyword.get(dictionary, :"$callers", [])
          nil -> []
        end

      Enum.any?(
        Enum.filter(List.wrap(callers), &is_pid/1),
        &owned_process?(&1, root, visited, depth + 1)
      )
    end
  end

  defp finish(%{active: active} = data, {:ok, candidate, directives} = result)
       when not is_map_key(active, :configuration_checked) do
    changed = Jido.Agent.Mutation.changed_plugins(data.agent, candidate, directives)

    paused =
      Enum.filter(
        data.plugin_specs,
        &(&1.module in changed and match?(%{runtime?: true}, &1.agent_server))
      )

    active =
      Map.merge(active, %{
        configuration_checked: true,
        paused_plugins: paused,
        changed_plugins: changed,
        diff: Jido.Agent.Diff.between(data.agent, candidate),
        result: result
      })

    data = %{data | active: active}

    if paused == [],
      do: finish(data, result),
      else:
        operation(:reconfigure, data, fn ->
          CompositionRuntime.pause(paused, data.plugin_refs, :quiesce)
        end)
  end

  defp finish(%{active: %{paused_plugins: [_ | _] = paused}} = data, {:error, _} = result) do
    data = put_in(data.active.result, result)

    operation(:resume_plugins, data, fn ->
      CompositionRuntime.pause(paused, data.plugin_refs, :resume)
    end)
  end

  defp finish(%{persistence: persistence} = data, {:ok, candidate, _} = result)
       when persistence not in [nil, false] do
    cancel_timer(data.active)
    deadline = System.monotonic_time(:millisecond) + data.persistence_timeout

    timer =
      Process.send_after(
        self(),
        {:persistence_timeout, data.active.turn_id},
        data.persistence_timeout
      )

    active = Map.merge(data.active, %{result: result, storage: {timer, deadline}})

    opts =
      durable_options(data) ++
        [revision: data.state_version + 1, expected_revision: data.state_version]

    operation(:save, %{data | active: active}, fn ->
      Jido.Persistence.save_agent(persistence, candidate, opts)
    end)
  end

  defp finish(data, {:ok, _, _} = result), do: publish_commit(data, result)
  defp finish(data, result), do: finish_result(data, result)

  defp stop_durable(data, reason),
    do: stop_failed(data, execution_error("Required durable commit failed", reason), :saving)

  defp publish_commit(data, {:ok, candidate, _directives} = result) do
    case ServerSupervisor.publish_checkpoint(
           data.activation_state,
           candidate,
           data.state_version + 1
         ) do
      :ok ->
        finish_result(data, result)

      {:error, reason} ->
        stop_failed(data, execution_error("Local checkpoint failed", reason), :checkpoint)
    end
  end

  defp finish_result(data, result) do
    {next, status, stage, count} =
      case result do
        {:ok, candidate, directives} ->
          changed = data.active.changed_plugins

          {:ok, specs} =
            Jido.Plugin.Normalizer.normalize_all(Jido.Agent.runtime_plugins(candidate))

          active =
            Map.merge(data.active, %{
              changed_plugins: changed,
              composition_changed:
                TopologyRuntime.changed?(data.active.diff, data.agent, candidate),
              commit_plugins: Enum.reject(specs, &(&1.module in changed))
            })

          {%{
             data
             | agent: candidate,
               plugin_specs: specs,
               active: active,
               state_version: data.state_version + 1,
               error_count: 0
           }, :succeeded, :commit, length(directives)}

        {:error, reason} ->
          if is_nil(data.active.from),
            do:
              Logger.warning("AgentServer cast turn failed",
                agent_id: data.agent.id,
                turn_id: data.active.turn_id
              )

          status =
            case reason do
              :cancelled -> :cancelled
              :turn_timeout -> :timed_out
              _ -> :failed
            end

          errors = data.error_count + if(status == :failed, do: 1, else: 0)
          {%{data | error_count: errors}, status, data.active.failure_stage || :cleaning, 0}
      end

    cancel_timer(data.active)

    next =
      next
      |> put_in([:active, :result], result)
      |> record_outcome(status, stage, status == :succeeded, count)

    case result do
      {:ok, _, directives} ->
        effects = Enum.reject(directives, &Jido.Agent.Mutation.mutation?/1)

        if next.active.composition_changed or next.active.changed_plugins != [] do
          begin_reconciliation(next, effects)
        else
          if effects != [] or Callbacks.commit_specs(next.plugin_specs) != [],
            do: begin_effects(next, effects),
            else: complete_terminal(next, :continue)
        end

      {:error, _} when status == :failed ->
        apply_failure_policy(next)

      _ ->
        complete_terminal(next, :continue)
    end
  end

  defp validate_batch(directives, config) do
    limit = config.max_directives_per_turn

    if limit != :infinity and length(directives) > limit do
      {:error, :too_many_directives}
    else
      Enum.reduce_while(Enum.with_index(directives), :ok, fn {directive, index}, :ok ->
        result =
          if match?(%ServerStop{}, directive) and index != length(directives) - 1,
            do: {:error, :terminal_directive_not_last},
            else: validate_effect(directive, config)

        case result do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp validate_effect(%{__struct__: module}, _)
       when module in [
              Directive.AgentAdd,
              Directive.AgentUpdate,
              Directive.AgentReplace,
              Directive.AgentRemove,
              Directive.RouteAdd,
              Directive.RouteUpdate,
              Directive.RouteReplace,
              Directive.RouteRemove,
              Directive.RoutesReorder,
              Directive.RoutesSet,
              Directive.ConnectionAdd,
              Directive.ConnectionUpdate,
              Directive.ConnectionReplace,
              Directive.ConnectionRemove,
              Directive.TopologySet,
              Directive.PluginAdd,
              Directive.PluginConfigure,
              Directive.PluginRemove
            ],
       do: :ok

  defp validate_effect(%Emit{dispatch: dispatch}, config),
    do: validate_dispatch(dispatch || config.default_dispatch)

  defp validate_effect(%AgentStart{} = directive, config),
    do: Jido.AgentServer.RuntimeDirectives.validate_start(directive, config)

  defp validate_effect(%AgentStop{name: name}, config),
    do: Jido.AgentServer.RuntimeDirectives.validate_runtime_target(name, config)

  defp validate_effect(%AgentSend{name: name}, config),
    do: Jido.AgentServer.RuntimeDirectives.validate_target(name, config)

  defp validate_effect(%OwnerSend{}, %{parent: nil}), do: {:error, :owner_not_found}
  defp validate_effect(%OwnerSend{}, _), do: :ok

  defp validate_effect(%ServerStop{}, _), do: :ok
  defp validate_effect(%ErrorReport{}, _), do: :ok

  defp validate_effect(%ProcessStart{child_spec: spec}, config) do
    if is_nil(config.jido) do
      {:error, :jido_instance_required}
    else
      child = Supervisor.child_spec(spec, [])

      case :supervisor.check_childspecs([child]) do
        :ok -> :ok
        _ -> {:error, :invalid_child_spec}
      end
    end
  catch
    _, _ -> {:error, :invalid_child_spec}
  end

  defp validate_effect(directive, config) do
    owner = directive_owner(config.plugin_specs, directive)

    cond do
      Directive.built_in?(directive) ->
        {:error, :unsupported_directive}

      not is_nil(owner) ->
        :ok

      is_function(config.directive_handler, 2) ->
        :ok

      not is_nil(Jido.Plugin.directive_owner(config.plugin_specs, directive)) ->
        :ok

      true ->
        {:error, :unsupported_directive}
    end
  end

  defp directive_owner(specs, directive) do
    case Jido.Plugin.directive_owner(specs, directive) do
      %{agent_server: %{dispatch?: true}} = owner -> owner
      _ -> nil
    end
  end

  defp begin_reconciliation(data, effects) do
    owner = self()
    replies = reply(data.active.from, data.active.result) ++ cancel_replies(data.active, :ok)

    active =
      Map.merge(data.active, %{
        from: nil,
        cancel_waiters: [],
        effects: effects,
        reconciling: true,
        effect_deadline: System.monotonic_time(:millisecond) + data.readiness_timeout,
        effect_timer:
          Process.send_after(
            self(),
            {:composition_timeout, data.active.turn_id},
            data.readiness_timeout
          )
      })

    data = %{data | active: active}
    runtime = Map.put(data, :owner, owner)

    {:next_state, phase, next} =
      operation(:reconcile, data, fn ->
        with {:ok, refs} <-
               CompositionRuntime.plugins(runtime, owner, data.active.changed_plugins),
             {:ok, members} <- CompositionRuntime.reconcile(runtime),
             do: {:ok, refs, members}
      end)

    {:next_state, phase, next, replies}
  end

  defp begin_effects(data, directives) do
    active = data.active
    replies = reply(active.from, active.result) ++ cancel_replies(active, :ok)

    hooks = Callbacks.commit_specs(Map.get(active, :commit_plugins, data.plugin_specs))
    timeout = if hooks == [], do: data.directive_timeout, else: data.commit_timeout
    timer_kind = if hooks == [], do: :effect_timeout, else: :commit_timeout

    active = %{
      active
      | from: nil,
        commit_hooks: hooks,
        cancel_waiters: [],
        effects: directives,
        effect_deadline: System.monotonic_time(:millisecond) + timeout,
        effect_timer: Process.send_after(self(), {timer_kind, active.turn_id}, timeout)
    }

    Semantic.point([:jido, :agent_server, :effects, :start], active.span.metadata, %{
      directive_count: length(directives)
    })

    {:next_state, :effects, %{data | active: active},
     replies ++ [{:next_event, :internal, :effect_next}]}
  end

  defp next_effect(data) do
    active = data.active

    cond do
      System.monotonic_time(:millisecond) >= active.effect_deadline ->
        finish_effects(data, :timed_out)

      active.commit_hooks != [] ->
        [plugin | _] = active.commit_hooks

        commit = %Jido.AgentServer.Plugin.Commit{
          plugin: plugin.module,
          turn_id: active.turn_id,
          agent_id: data.agent.id,
          agent_module: data.agent.module,
          plugin_state: owned_plugin_state(data.agent, plugin),
          state_version: data.state_version,
          jido: data.jido,
          partition: data.partition
        }

        ref = Map.get(data.plugin_refs, plugin.module)
        operation(:commit_hook, data, fn -> Callbacks.after_commit(plugin, ref, commit) end)

      active.effect_index == length(active.effects) ->
        finish_effects(data, :succeeded)

      true ->
        directive = Enum.at(active.effects, active.effect_index)
        handler = data.directive_handler

        context = %{
          agent: data.agent,
          activation_state: data.activation_state,
          parent: data.parent,
          jido: data.jido,
          partition: data.partition,
          server: self(),
          turn_id: active.turn_id,
          signal_id: active.signal_id,
          state_version: data.state_version,
          default_dispatch: data.default_dispatch
        }

        owner = directive_owner(data.plugin_specs, directive)
        ref = if owner, do: Map.get(data.plugin_refs, owner.module)

        plugin_context =
          if owner do
            %Jido.Plugin.DirectiveContext{
              turn_id: active.turn_id,
              agent_id: data.agent.id,
              source_signal: active.source_signal,
              effective_signal: active.prepared.signal,
              state_version: data.state_version,
              plugin_state: owned_plugin_state(data.agent, owner),
              turn_context: active.turn_context,
              jido: data.jido,
              partition: data.partition
            }
          end

        operation(:effect, data, fn ->
          if owner,
            do: Callbacks.dispatch(owner, ref, directive, plugin_context),
            else: run_effect(directive, handler, context)
        end)
    end
  end

  defp run_effect(directive, handler, context) do
    case directive do
      %Emit{signal: signal, dispatch: dispatch} ->
        {:ok, signal} = TraceContext.propagate_to(signal, context.signal_id)

        case dispatch do
          nil ->
            TopologyRuntime.emit(context, signal)

          target ->
            Signal.Dispatch.dispatch(
              signal,
              DispatchPreparation.inherit_bus_scope(target, context.jido)
            )
        end

      %AgentStart{} = directive ->
        Jido.AgentServer.RuntimeDirectives.start(directive, context)

      %AgentStop{name: name, reason: reason} ->
        stop_child(context.server, name, reason)

      %AgentSend{name: name, signal: signal} ->
        TopologyRuntime.send_agent(context.activation_state, name, signal)

      %OwnerSend{signal: signal} ->
        TopologyRuntime.owner_send(context.parent, signal)

      %ServerStop{reason: reason} ->
        {:stop, reason}

      %ErrorReport{error: error, context: error_context} ->
        {:reported_error, {:reported_error, error_context, error}}

      %ProcessStart{child_spec: spec} ->
        case DynamicSupervisor.start_child(Jido.agent_supervisor_name(context.jido), spec) do
          {:ok, _} -> :ok
          {:ok, _, _} -> :ok
          :ignore -> :ok
          _ -> {:error, :spawn_process_failed}
        end

      custom when is_function(handler, 2) ->
        handler.(custom, context)

      _state_only_plugin ->
        :ok
    end
  catch
    _, _ -> {:error, :directive_failed}
  end

  defp effect_status(nil), do: nil
  defp effect_status(%{effect_deadline: nil}), do: nil
  defp effect_status(active), do: %{total: length(active.effects), completed: active.effect_index}

  defp record_effects(data, status) do
    active = data.active

    outcome = %{
      turn_id: active.turn_id,
      status: status,
      completed: active.effect_index,
      total: length(active.effects),
      committed_version: data.state_version,
      stage: if(active.commit_hooks == [], do: :directive, else: :after_commit)
    }

    Semantic.point(
      [:jido, :agent_server, :effects, :stop],
      Map.merge(active.span.metadata, %{
        committed?: true,
        stage: outcome.stage,
        status: telemetry_status(status)
      }),
      %{directive_completed: active.effect_index, directive_count: length(active.effects)}
    )

    data |> Map.put(:last_effect_outcome, outcome) |> put_in([:active, :effect_outcome], outcome)
  end

  defp finish_effects(data, status) do
    Process.cancel_timer(data.active.effect_timer)
    data = record_effects(data, status)
    TraceContext.clear()
    idle_transition(%{data | active: nil})
  end

  defp record_outcome(data, status, stage, committed, count) do
    active = data.active

    outcome = %{
      turn_id: active.turn_id,
      signal_id: active.signal_id,
      status: status,
      stage: stage,
      committed?: committed,
      state_version_before: active.start_version,
      state_version_after: data.state_version,
      directive_count: count,
      duration_ms:
        System.convert_time_unit(
          max(System.monotonic_time() - active.span.at, 0),
          :native,
          :millisecond
        )
    }

    metadata = %{
      status: telemetry_status(status),
      stage: if(committed, do: :commit, else: :evaluate),
      committed?: committed
    }

    measurements = %{
      state_version_before: active.start_version,
      state_version_after: data.state_version,
      directive_count: count
    }

    if committed do
      Semantic.point(
        [:jido, :agent_server, :commit],
        Map.merge(active.span.metadata, metadata),
        measurements
      )

      Semantic.point([:jido, :agent_server, :directives, :returned], active.span.metadata, %{
        directive_count: count
      })
    end

    Semantic.finish(active.span, metadata, measurements)

    Semantic.point(
      [:jido, :agent_server, :turn, :settled],
      Map.merge(active.span.metadata, metadata),
      measurements
    )

    history =
      if data.debug do
        queue = :queue.in(outcome, data.history)
        if :queue.len(queue) > data.debug_max_events, do: elem(:queue.out(queue), 1), else: queue
      else
        data.history
      end

    data
    |> Map.merge(%{last_outcome: outcome, history: history})
    |> put_in([:active, :outcome], outcome)
  end

  defp telemetry_status(:succeeded), do: :ok
  defp telemetry_status(:failed), do: :error
  defp telemetry_status(status), do: status

  defp apply_failure_policy(%{error_policy: :log_only} = data),
    do: complete_terminal(data, :continue)

  defp apply_failure_policy(%{error_policy: :stop_on_error} = data),
    do: complete_terminal(data, {:stop, :agent_error})

  defp apply_failure_policy(%{error_policy: {:max_errors, max}} = data),
    do:
      complete_terminal(
        data,
        if(data.error_count >= max, do: {:stop, :max_agent_errors}, else: :continue)
      )

  defp apply_failure_policy(
         %{error_policy: {:emit_signal, _}, active: %{signal_type: @error_signal}} = data
       ),
       do: complete_terminal(data, :continue)

  defp apply_failure_policy(data) do
    policy = data.error_policy
    active = data.active
    error = elem(active.result, 1)
    agent_id = data.agent.id
    jido = data.jido

    timer =
      Process.send_after(self(), {:policy_timeout, active.turn_id}, data.error_policy_timeout)

    data =
      data
      |> put_in([:active, :policy_timer], timer)
      |> put_in(
        [:active, :policy_deadline],
        System.monotonic_time(:millisecond) + data.error_policy_timeout
      )

    operation(:policy, data, fn ->
      summary =
        if active.effect_outcome,
          do: Map.merge(active.outcome, %{status: :failed, stage: :directive}),
          else: active.outcome

      try do
        case policy do
          {:emit_signal, target} ->
            signal = Signal.new!(@error_signal, summary, source: "/agent/#{agent_id}")

            signal =
              case Jido.Tracing.Context.propagate_to(signal, active.signal_id) do
                {:ok, traced} -> traced
                _ -> signal
              end

            case Jido.Signal.Dispatch.dispatch(
                   signal,
                   DispatchPreparation.inherit_bus_scope(target, jido)
                 ) do
              :ok -> :continue
              _ -> {:stop, :error_signal_failed}
            end

          fun ->
            fun.(error, summary)
        end
      rescue
        _ -> {:stop, :error_policy_failed}
      catch
        _, _ -> {:stop, :error_policy_failed}
      end
    end)
  end

  defp complete_terminal(data, decision) do
    if data.active.policy_timer, do: Process.cancel_timer(data.active.policy_timer)
    replies = reply(data.active.from, data.active.result) ++ cancel_replies(data.active, :ok)
    TraceContext.clear()
    next = %{data | active: nil}

    case decision do
      :continue ->
        idle_transition(next, replies)

      {:stop, reason} when is_atom(reason) ->
        {:stop_and_reply, {:shutdown, reason}, replies, next}

      _ ->
        {:stop_and_reply, {:shutdown, :invalid_error_policy_result}, replies, next}
    end
  end

  defp runtime_value(nil, _key, default), do: default

  defp runtime_value(table, key, default) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  defp persist_runtime(nil, _key, _value), do: :ok
  defp persist_runtime(table, key, value), do: :ets.insert(table, {key, value})

  defp monitor_owners(table),
    do: Map.new(runtime_value(table, :owners, []), &{&1, Process.monitor(&1)})

  defp set_admission(data, mode) do
    persist_runtime(data.activation_state, :admission, mode)
    %{data | admission_mode: mode}
  end

  defp control_caller?(from, data) do
    {caller, _} = from

    reentrant?({:call, from}, data) or bootstrap_caller?(from, data) or
      Enum.any?([data.parent_effect, data.control], fn operation ->
        operation != nil and operation.task != nil and
          owned_process?(caller, operation.task.pid, [], 0)
      end)
  end

  defp settled?(data),
    do: data.active == nil and data.parent_effect == nil and MapSet.size(data.postponed) == 0

  defp begin_control(phase, data, kind, from, policy, timeout) do
    token = make_ref()

    control = %{
      kind: kind,
      from: from,
      prior: data.admission_mode,
      token: token,
      timer: Process.send_after(self(), {:control_timeout, token}, timeout),
      deadline: System.monotonic_time(:millisecond) + timeout,
      task: nil
    }

    data = data |> cancel_idle() |> set_admission(:quiescing) |> Map.put(:control, control)

    replies =
      Enum.flat_map(data.queued_from, fn {_token, type} ->
        turn_rejection(type, :quiesced, data)
      end)

    data = %{data | queued_from: %{}}
    progress = replies ++ [{:next_event, :internal, :control_progress}]

    if policy == :cancel and data.active != nil and phase not in [:saving, :policy, :effects] do
      case abort_turn(phase, data, :cancelled) do
        {:next_state, next_phase, next} -> {:next_state, next_phase, next, progress}
        {:keep_state, next} -> {:keep_state, next, progress}
      end
    else
      # Reject waiting callers now. OTP drains their postponed events on the
      # next phase change; resume waits for that drain before opening admission.
      {:keep_state, data, progress}
    end
  end

  defp control_progress(data) do
    cond do
      data.control != nil and System.monotonic_time(:millisecond) >= data.control.deadline ->
        control_timeout(data)

      data.admission_mode == :quiescing and settled?(data) ->
        case data.control do
          nil ->
            {:keep_state, set_admission(data, :quiesced)}

          %{kind: :quiesce} = control ->
            Process.cancel_timer(control.timer)

            {:keep_state, data |> set_admission(:quiesced) |> Map.put(:control, nil),
             reply(control.from, :ok)}

          %{task: nil} ->
            opts =
              Keyword.merge(durable_options(data),
                revision: data.state_version,
                expected_revision: data.state_version
              )

            # Recovery must not reopen an interrupted writer. Keep this marker
            # before starting storage, including the write-before-reply window.
            persist_runtime(data.activation_state, :admission, :blocked)

            deadline =
              min(
                data.control.deadline,
                System.monotonic_time(:millisecond) + data.persistence_timeout
              )

            Process.cancel_timer(data.control.timer)

            timer =
              Process.send_after(
                self(),
                {:control_timeout, data.control.token},
                remaining_wait(deadline)
              )

            source = data.persistence
            agent = data.agent
            task = Task.async(fn -> Jido.Persistence.save_agent(source, agent, opts) end)

            {:keep_state,
             %{data | control: %{data.control | task: task, timer: timer, deadline: deadline}}}

          _ ->
            :keep_state_and_data
        end

      true ->
        :keep_state_and_data
    end
  end

  defp control_timeout(data) do
    if data.control.task do
      Task.shutdown(data.control.task, :brutal_kill)
      control_failed(data, :indeterminate, false)
    else
      result =
        if data.control.kind == :hibernate,
          do: hibernate_error(:quiesce_timeout, true),
          else: {:error, :quiesce_timeout}

      replies = reply(data.control.from, result)

      {:keep_state, %{data | control: nil},
       replies ++ [{:next_event, :internal, :control_progress}]}
    end
  end

  defp hibernate_error(reason, safe?), do: {:error, %{reason: reason, resumable?: safe?}}

  defp control_failed(data, reason, safe?) do
    control = data.control
    Process.cancel_timer(control.timer)
    mode = if safe?, do: if(control.prior == :open, do: :open, else: :quiesced), else: :blocked
    # A failed idle save closes admission. Do not start an automatic retry loop.
    mode = if control.from == nil and mode == :open, do: :quiesced, else: mode
    data = data |> set_admission(mode) |> Map.put(:control, nil) |> arm_idle()
    {:keep_state, data, reply(control.from, hibernate_error(reason, safe?))}
  end

  defp idle_transition(data, replies \\ []) do
    {:next_state, :idle, arm_idle(data), replies ++ [{:next_event, :internal, :control_progress}]}
  end

  defp cancel_idle(%{idle_timer: nil} = data), do: data

  defp cancel_idle(data) do
    {timer, _} = data.idle_timer
    Process.cancel_timer(timer)
    %{data | idle_timer: nil}
  end

  defp arm_idle(data) do
    data = cancel_idle(data)

    if data.idle_timeout != :infinity and data.admission_mode == :open and
         map_size(data.owners) == 0 and settled?(data) do
      token = make_ref()
      timer = Process.send_after(self(), {:idle_timeout, token}, data.idle_timeout)
      %{data | idle_timer: {timer, token}}
    else
      data
    end
  end

  defp cancel_timer(%{timer: nil}), do: :ok
  defp cancel_timer(active), do: Process.cancel_timer(active.timer)

  defp cancel_replies(active, result),
    do: Enum.flat_map(active.cancel_waiters, &reply(&1, result))

  defp reply(nil, _result), do: []
  defp reply(from, result), do: [{:reply, from, result}]

  defp active_status(nil, _phase), do: nil

  defp active_status(active, phase),
    do:
      active
      |> Map.take([:turn_id, :signal_id, :start_version])
      |> Map.put(
        :committed_version,
        if(active.outcome && active.outcome.committed?,
          do: active.outcome.state_version_after,
          else: nil
        )
      )
      |> Map.put(:stage, phase)
      |> Map.put(:worker_pid, active.worker)

  defp complete_task(task) do
    Process.demonitor(task.ref, [:flush])
    Process.unlink(task.pid)
    :ok
  end
end
