defmodule Jido.AgentServer do
  @moduledoc """
  GenServer runtime for Jido agents.

  AgentServer is the "Act" side of the Jido framework: while Agents "think"
  (pure decision logic via `cmd/2`), AgentServer "acts" by executing the
  directives they emit. Signal routing happens in AgentServer, keeping
  Agents purely action-oriented.

  ## Architecture

  - Single GenServer per agent under `Jido.AgentSupervisor`
  - Internal directive queue with drain loop for non-blocking processing
  - Registry-based naming via `Jido.Registry`
  - Logical parent-child hierarchy via state tracking + monitors

  ## Public API

  - `start/1` - Start under DynamicSupervisor
  - `start_link/1` - Start linked to caller
  - `call/3` - Synchronous signal processing
  - `cast/2` - Asynchronous signal processing
  - `state/1` - Get full State struct
  - `whereis/1` - Registry lookup by ID (default registry)
  - `whereis/2` - Registry lookup by ID (specific registry)

  ## Signal Flow

  ```
  Signal → AgentServer.call/cast
        → route_signal_to_action (via strategy.signal_routes or default)
        → Agent.cmd/2
        → {agent, directives}
        → Directives queued
        → Drain loop executes via DirectiveExec protocol
  ```

  Signal routing is owned by AgentServer, not the Agent. Strategies can define
  `signal_routes/1` to map signal types to strategy commands. Unmatched signals
  fall back to `{signal.type, signal.data}` as the action.

  ## Options

  - `:jido` - Jido instance name for registry scoping (default: `Jido`)
  - `:agent` - Agent module or struct (required)
  - `:id` - Instance ID (auto-generated if not provided)
  - `:initial_state` - Initial state map for agent
  - `:registry` - Registry module (default: `Jido.Registry`)
  - `:default_dispatch` - Default dispatch config for Emit directives
  - `:error_policy` - Error handling policy
  - `:max_queue_size` - Max directive queue size (default: 10_000)
  - `:parent` - Parent reference for hierarchy
  - `:on_parent_death` - Behavior when parent dies (`:stop`, `:continue`, `:emit_orphan`)
  - `:spawn_fun` - Custom function for spawning children
  - `:debug` - Enable debug mode with event buffer (default: `false`)

  ## Agent Resolution

  The `:agent` option accepts:

  - **Module name** - Must implement `new/0` or `new/1`
    - `new/1` receives `[id: id, state: initial_state]` as keyword options
    - `new/0` creates agent with defaults; `:id` and `:initial_state` options are ignored
  - **Agent struct** - Used directly
    - Provide `:agent_module` option to specify the module if it differs from `agent.__struct__`
    - The struct's ID takes precedence over the `:id` option

  The `:agent_module` option is only used when `:agent` is a struct. It tells AgentServer which module implements the agent behavior (for calling `cmd/2`, lifecycle hooks, etc.).

  ## Examples

      # Using global Jido instance (default)
      {:ok, pid} = AgentServer.start_link(agent: SimpleAgent)

      # Using a named Jido instance
      {:ok, pid} = AgentServer.start_link(jido: MyApp.Jido, agent: MyAgent)

      # Module with new/1 - receives id and state
      {:ok, pid} = AgentServer.start_link(
        agent: MyAgent,
        id: "my-id",
        initial_state: %{counter: 42}
      )

      # Pre-built struct - requires agent_module
      agent = MyAgent.new(id: "prebuilt", state: %{value: 99})
      {:ok, pid} = AgentServer.start_link(agent: agent, agent_module: MyAgent)

  ## Completion Detection

  Agents signal completion via **state**, not process death:

      # In your strategy/agent, set terminal status:
      agent = put_in(agent.state.status, :completed)
      agent = put_in(agent.state.last_answer, answer)

      # External code polls for completion:
      {:ok, state} = AgentServer.state(server)
      case state.agent.state.status do
        :completed -> state.agent.state.last_answer
        :failed -> {:error, state.agent.state.error}
        _ -> :still_running
      end

  This follows Elm/Redux semantics where completion is a state concern.
  The process stays alive until explicitly stopped or supervised.

  **Do NOT** use `{:stop, ...}` from DirectiveExec for normal completion—this
  causes race conditions with async work and skips lifecycle hooks.
  See `Jido.AgentServer.DirectiveExec` for details.

  ## Debugging

  AgentServer can record recent events in an in-memory ring buffer (max 50)
  to help diagnose what happened inside a running agent.

  Enable at start:

      {:ok, pid} = AgentServer.start_link(agent: MyAgent, debug: true)

  Or toggle at runtime:

      :ok = AgentServer.set_debug(pid, true)

  Retrieve recent events (newest-first):

      {:ok, events} = AgentServer.recent_events(pid, limit: 10)

  Each event has the shape `%{at: monotonic_ms, type: atom(), data: map()}`.
  Event types include `:signal_received` and `:directive_started`.

  Returns `{:error, :debug_not_enabled}` if debug mode is off.

  > **Note:** This is a development aid, not an audit log. Events are not
  > persisted and the buffer has fixed capacity.

  ## Timeout Diagnostics

  When `await_completion/2` times out, it returns a diagnostic map:

      {:error, {:timeout, %{
        hint: "Agent is idle but await_completion is blocking",
        server_status: :idle,
        queue_length: 0,
        iteration: nil,
        waited_ms: timeout_ms
      }}}

  Use this to understand why the agent hasn't completed:
  - `:idle` with empty queue → agent finished but state doesn't match await condition
  - `:waiting` → strategy is waiting (e.g., for LLM response)
  - `:running` → still processing directives
  """

  use GenServer

  require Logger

  alias Jido.AgentServer.{
    ChildInfo,
    DirectiveExec,
    Options,
    ParentRef,
    SignalRouter,
    State,
    Status
  }

  alias Jido.Agent.Directive
  alias Jido.AgentServer.Signal.{ChildExit, ChildStarted, Orphaned}
  alias Jido.AgentServer.State.Lifecycle
  alias Jido.Runtime.Tasking
  alias Jido.RuntimeDefaults
  alias Jido.Sensor.Runtime, as: SensorRuntime
  alias Jido.Signal
  alias Jido.Signal.Router, as: JidoRouter
  alias Jido.Tracing.Context, as: TraceContext
  alias Jido.Tracing.Trace

  @type server :: pid() | atom() | {:via, module(), term()}
  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts an AgentServer under `Jido.AgentSupervisor`.

  ## Examples

      {:ok, pid} = Jido.AgentServer.start(agent: MyAgent)
      {:ok, pid} = Jido.AgentServer.start(agent: MyAgent, id: "my-agent")
  """
  @spec start(keyword() | map()) :: DynamicSupervisor.on_start_child()
  def start(opts) do
    {child_spec_overrides, start_opts} = extract_child_spec_overrides(opts)
    child_spec = build_child_spec(start_opts, child_spec_overrides)
    supervisor = resolve_supervisor(start_opts)
    start_under_supervisor(supervisor, child_spec)
  end

  defp build_child_spec(start_opts, []), do: {__MODULE__, start_opts}

  defp build_child_spec(start_opts, overrides),
    do: Supervisor.child_spec({__MODULE__, start_opts}, overrides)

  defp resolve_supervisor(start_opts) do
    jido_instance =
      if is_list(start_opts), do: Keyword.get(start_opts, :jido), else: Map.get(start_opts, :jido)

    case jido_instance do
      nil -> Jido.AgentSupervisor
      instance -> Jido.agent_supervisor_name(instance)
    end
  end

  defp start_under_supervisor(supervisor, child_spec) do
    with {:ok, _pid} <- maybe_whereis_supervisor(supervisor),
         result <- safe_dynamic_supervisor_start_child(supervisor, child_spec) do
      case result do
        {:error, :not_found} -> {:error, {:missing_supervisor, supervisor}}
        other -> other
      end
    else
      {:error, :not_found} -> {:error, {:missing_supervisor, supervisor}}
    end
  end

  defp extract_child_spec_overrides(opts) when is_list(opts) do
    {restart, start_opts} = Keyword.pop(opts, :restart)
    overrides = if is_nil(restart), do: [], else: [restart: restart]
    {overrides, start_opts}
  end

  defp extract_child_spec_overrides(opts) when is_map(opts) do
    {restart, start_opts} = Map.pop(opts, :restart)
    overrides = if is_nil(restart), do: [], else: [restart: restart]
    {overrides, start_opts}
  end

  @doc """
  Starts an AgentServer linked to the calling process.

  ## Options

  See module documentation for full list of options.

  ## Examples

      {:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent)
      {:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent, id: "custom-123")
      {:ok, pid} = Jido.AgentServer.start_link(jido: MyApp.Jido, agent: MyAgent)
  """
  @spec start_link(keyword() | map()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) or is_map(opts) do
    # Extract GenServer options (like :name) from agent opts
    {genserver_opts, agent_opts} = extract_genserver_opts(opts)
    GenServer.start_link(__MODULE__, agent_opts, genserver_opts)
  end

  defp extract_genserver_opts(opts) when is_list(opts) do
    case Keyword.pop(opts, :name) do
      {nil, agent_opts} -> {[], agent_opts}
      {name, agent_opts} -> {[name: name], agent_opts}
    end
  end

  defp extract_genserver_opts(opts) when is_map(opts) do
    case Map.pop(opts, :name) do
      {nil, agent_opts} -> {[], agent_opts}
      {name, agent_opts} -> {[name: name], agent_opts}
    end
  end

  @doc """
  Returns a child_spec for supervision.
  """
  @spec child_spec(keyword() | map()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = opts[:id] || __MODULE__

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: RuntimeDefaults.agent_server_shutdown_timeout(),
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Synchronously sends a signal and waits for processing.

  Returns the updated agent struct after signal processing.
  Directives are still executed asynchronously via the drain loop.

  ## Returns

  * `{:ok, agent}` - Signal processed successfully
  * `{:error, :not_found}` - Server not found via registry
  * `{:error, :invalid_server}` - Unsupported server reference
  * Exits with `{:noproc, ...}` if process dies during call

  ## Examples

      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      server = Jido.AgentServer.via_tuple("agent-id", Jido.Registry)
      {:ok, agent} = Jido.AgentServer.call(server, signal, 10_000)

      {:ok, pid} = Jido.AgentServer.whereis("agent-id")
      {:ok, agent} = Jido.AgentServer.call(pid, signal, 10_000)
  """
  @spec call(server(), Signal.t(), timeout()) :: {:ok, struct()} | {:error, term()}
  def call(server, %Signal{} = signal, timeout \\ RuntimeDefaults.agent_server_call_timeout()) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_call(server_ref, {:signal, signal}, timeout)
    end
  end

  @doc """
  Asynchronously sends a signal for processing.

  Returns immediately. The signal is processed in the background.

  ## Returns

  * `:ok` - Signal queued successfully
  * `{:error, :not_found}` - Server not found via registry
  * `{:error, :invalid_server}` - Unsupported server reference

  ## Examples

      :ok = Jido.AgentServer.cast(pid, signal)

      server = Jido.AgentServer.via_tuple("agent-id", Jido.Registry)
      :ok = Jido.AgentServer.cast(server, signal)

      {:ok, pid} = Jido.AgentServer.whereis("agent-id")
      :ok = Jido.AgentServer.cast(pid, signal)
  """
  @spec cast(server(), Signal.t()) :: :ok | {:error, term()}
  def cast(server, %Signal{} = signal) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_cast(server_ref, {:signal, signal})
    end
  end

  @doc """
  Gets the full State struct for an agent.

  ## Returns

  * `{:ok, state}` - Full State struct retrieved
  * `{:error, :not_found}` - Server not found via registry
  * `{:error, :invalid_server}` - Unsupported server reference

  ## Examples

      {:ok, state} = Jido.AgentServer.state(pid)

      server = Jido.AgentServer.via_tuple("agent-id", Jido.Registry)
      {:ok, state} = Jido.AgentServer.state(server)

      {:ok, pid} = Jido.AgentServer.whereis("agent-id")
      {:ok, state} = Jido.AgentServer.state(pid)
  """
  @spec state(server()) :: {:ok, State.t()} | {:error, term()}
  def state(server) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_call(server_ref, :get_state)
    end
  end

  @doc """
  Wait for an agent to reach a terminal status (`:completed` or `:failed`).

  This is an event-driven wait - the caller blocks until the agent's state
  transitions to a terminal status, then receives the result immediately.
  No polling is involved.

  ## Options

  - `:status_path` - Path to status field in agent.state (default: `[:status]`)
  - `:result_path` - Path to result field (default: `[:last_answer]`)
  - `:error_path` - Path to error field (default: `[:error]`)

  ## Returns

  - `{:ok, %{status: :completed | :failed, result: any()}}` - Agent reached terminal status
  - `{:error, :not_found}` - Server not found
  - `{:error, {:timeout, map()}}` - Completion timeout with diagnostics

  ## Examples

      {:ok, result} = AgentServer.await_completion(pid, timeout: 10_000)
  """
  @spec await_completion(server(), keyword()) :: {:ok, map()} | {:error, term()}
  def await_completion(server, opts \\ []) do
    with {:ok, server_ref} <- resolve_server(server) do
      try do
        # Timeout semantics are handled by server-side waiter expiry to avoid
        # GenServer.call timeout reply leaks in caller mailboxes.
        GenServer.call(server_ref, {:await_completion, opts}, :infinity)
      catch
        :exit, {:timeout, _} ->
          {:error, :timeout}

        :exit, {:noproc, _} ->
          {:error, :not_found}

        :exit, {:normal, _} ->
          {:error, :not_found}

        :exit, {:shutdown, _} ->
          {:error, :not_found}

        :exit, :shutdown ->
          {:error, :not_found}
      end
    end
  end

  defp infer_timeout_hint(status) do
    case status do
      :waiting -> "Strategy is waiting (possibly for LLM response)"
      :running -> "Strategy is running (processing directives)"
      :idle -> "Agent is idle but await_completion is blocking"
      _ -> nil
    end
  end

  @doc """
  Gets runtime status for an agent process.

  Returns a `Status` struct combining the strategy snapshot with process metadata.
  This provides a stable API for querying agent status without depending on internal
  `__strategy__` state structure.

  ## Returns

  * `{:ok, status}` - Status struct with snapshot and metadata
  * `{:error, :not_found}` - Server not found via registry
  * `{:error, :invalid_server}` - Unsupported server reference

  ## Examples

      {:ok, agent_status} = Jido.AgentServer.status(pid)

      # Check completion
      if agent_status.snapshot.done? do
        IO.puts("Result: " <> inspect(agent_status.snapshot.result))
      end

      # Use delegate helpers
      case Status.status(agent_status) do
        :success -> {:done, Status.result(agent_status)}
        :failure -> {:error, Status.details(agent_status)}
        _ -> :continue
      end
  """
  @spec status(server()) :: {:ok, Status.t()} | {:error, term()}
  def status(server) do
    with {:ok, server_ref} <- resolve_server(server),
         {:ok, %State{agent: agent, agent_module: agent_module} = state} <-
           safe_call(server_ref, :get_state, RuntimeDefaults.status_call_timeout()) do
      snapshot = agent_module.strategy_snapshot(agent)

      {:ok,
       %Status{
         agent_module: agent_module,
         agent_id: state.id,
         pid: normalize_status_pid(server_ref),
         snapshot: snapshot,
         raw_state: agent.state
       }}
    end
  end

  @doc """
  Streams status updates by polling at regular intervals.

  Returns a Stream that yields status snapshots. Useful for monitoring agent
  execution without manual polling loops.

  ## Options

  - `:interval_ms` - Polling interval in milliseconds (default: runtime default, min 50ms)
  - `:on_error` - `:raise` (default), `:halt`, or `:emit`

  ## Examples

      # Poll until completion
      AgentServer.stream_status(pid, interval_ms: 50)
      |> Enum.reduce_while(nil, fn status, _acc ->
        case Status.status(status) do
          :success -> {:halt, {:ok, Status.result(status)}}
          :failure -> {:halt, {:error, Status.details(status)}}
          _ -> {:cont, nil}
        end
      end)

      # Take first 10 snapshots
      AgentServer.stream_status(pid)
      |> Enum.take(10)
  """
  @spec stream_status(server(), keyword()) :: Enumerable.t()
  def stream_status(server, opts \\ []) do
    interval_ms =
      max(50, Keyword.get(opts, :interval_ms, RuntimeDefaults.stream_status_interval_ms()))

    on_error = Keyword.get(opts, :on_error, :raise)

    Stream.resource(
      fn -> :running end,
      fn
        :halt ->
          {:halt, :halt}

        :running ->
          case status(server) do
            {:ok, agent_status} ->
              Process.sleep(interval_ms)
              {[agent_status], :running}

            {:error, reason} ->
              stream_status_error(on_error, reason)
          end
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Enables or disables debug mode at runtime.

  When debug mode is enabled, the agent records recent events in a ring buffer
  for diagnostic purposes.

  ## Examples

      :ok = AgentServer.set_debug(pid, true)
      # ... run some operations ...
      {:ok, events} = AgentServer.recent_events(pid)
  """
  @spec set_debug(server(), boolean()) :: :ok | {:error, term()}
  def set_debug(server, enabled) when is_boolean(enabled) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_call(server_ref, {:set_debug, enabled})
    end
  end

  @doc """
  Retrieves recent debug events from the agent's event buffer.

  Events are returned newest-first. Each event includes:
  - `:at` - Monotonic timestamp in milliseconds
  - `:type` - Event type atom (e.g., `:signal_received`, `:directive_started`)
  - `:data` - Event-specific data map

  Returns `{:error, :debug_not_enabled}` if debug mode is off.

  ## Options

  - `:limit` - Maximum number of events to return (default: all, max 50)

  ## Examples

      {:ok, events} = AgentServer.recent_events(pid, limit: 10)
  """
  @spec recent_events(server(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def recent_events(server, opts \\ []) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_call(server_ref, {:recent_events, opts})
    end
  end

  @doc """
  Looks up an agent by ID in a specific registry.

  Returns the pid if found, nil otherwise.

  ## Examples

      pid = Jido.AgentServer.whereis(MyApp.Jido.Registry, "agent-123")
      # => #PID<0.123.0>
  """
  @spec whereis(module(), String.t()) :: pid() | nil
  def whereis(registry, id) when is_atom(registry) and is_binary(id) do
    case safe_registry_lookup(registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Returns a via tuple for Registry-based naming.

  ## Examples

      name = Jido.AgentServer.via_tuple("agent-id", MyApp.Jido.Registry)
      GenServer.call(name, :get_state)
  """
  @spec via_tuple(String.t(), module()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(id, registry) when is_binary(id) and is_atom(registry) do
    {:via, Registry, {registry, id}}
  end

  @doc """
  Check if the agent server process is alive.
  """
  @spec alive?(server()) :: boolean()
  def alive?(server) when is_pid(server), do: Process.alive?(server)

  def alive?(server) do
    case status(server) do
      {:ok, _status} -> true
      {:error, _} -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Attachment API (for Jido.Agent.InstanceManager integration)
  # ---------------------------------------------------------------------------

  @doc """
  Attaches a process to this agent, tracking it as an active consumer.

  When attached, the agent will not idle-timeout. The agent monitors the
  attached process and automatically detaches it on exit.

  Used by `Jido.Agent.InstanceManager` to track LiveView sockets, WebSocket handlers,
  or any process that needs the agent to stay alive.

  ## Examples

      {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, key)
      :ok = Jido.AgentServer.attach(pid)

      # With explicit owner
      :ok = Jido.AgentServer.attach(pid, socket_pid)
  """
  @spec attach(server(), pid()) :: :ok | {:error, term()}
  def attach(server, owner_pid \\ self()) do
    with {:ok, server_ref} <- resolve_server(server) do
      try do
        GenServer.call(server_ref, {:attach, owner_pid})
      catch
        :exit, {:noproc, _} -> {:error, :not_found}
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, reason -> {:error, reason}
      end
    end
  end

  @doc """
  Detaches a process from this agent.

  If this was the last attachment and `idle_timeout` is configured,
  the idle timer starts.

  Note: You don't need to call this explicitly if the attached process
  exits normally — the monitor will handle cleanup automatically.

  ## Examples

      :ok = Jido.AgentServer.detach(pid)
  """
  @spec detach(server(), pid()) :: :ok | {:error, term()}
  def detach(server, owner_pid \\ self()) do
    with {:ok, server_ref} <- resolve_server(server) do
      try do
        GenServer.call(server_ref, {:detach, owner_pid})
      catch
        :exit, {:noproc, _} -> {:error, :not_found}
        :exit, {:timeout, _} -> {:error, :timeout}
        :exit, reason -> {:error, reason}
      end
    end
  end

  @doc """
  Touches the agent to reset the idle timer.

  Use this for request-based activity tracking (e.g., HTTP requests)
  where you don't want to maintain a persistent attachment.

  ## Examples

      # In a controller
      {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, key)
      :ok = Jido.AgentServer.touch(pid)
  """
  @spec touch(server()) :: :ok | {:error, term()}
  def touch(server) do
    with {:ok, server_ref} <- resolve_server(server) do
      safe_cast(server_ref, :touch)
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(raw_opts) do
    Process.flag(:trap_exit, true)

    opts = if is_map(raw_opts), do: Map.to_list(raw_opts), else: raw_opts

    with {:ok, options} <- Options.new(opts),
         {:ok, agent_module, agent} <- resolve_agent(options),
         {:ok, state} <- State.from_options(options, agent_module, agent),
         :ok <- register_server(state) do
      # Register in Registry
      :ok

      # Monitor parent if present
      state = maybe_monitor_parent(state)

      {:ok, state, {:continue, :post_init}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp register_server(%State{} = state) do
    case Registry.register(state.registry, state.id, %{}) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, pid}} when pid == self() ->
        :ok

      {:error, {:already_registered, pid}} when is_pid(pid) ->
        {:error, {:already_started, pid}}
    end
  rescue
    ArgumentError ->
      {:error, :invalid_registry}
  end

  @impl true
  def handle_continue(:post_init, state) do
    state =
      state
      |> initialize_strategy()
      |> build_signal_router()

    Process.send_after(self(), :post_init_start_children, 1)
    {:noreply, state}
  end

  defp init_signal do
    Signal.new!("jido.strategy.init", %{}, source: "/agent/system")
  end

  defp initialize_strategy(%State{} = state) do
    agent_module = state.agent_module

    if function_exported?(agent_module, :strategy, 0) do
      strategy = agent_module.strategy()

      strategy_opts =
        if function_exported?(agent_module, :strategy_opts, 0),
          do: agent_module.strategy_opts(),
          else: []

      ctx = %{agent_module: agent_module, strategy_opts: strategy_opts}
      {agent, directives} = strategy.init(state.agent, ctx)

      state = State.update_agent(state, agent)

      case State.enqueue_all(state, init_signal(), List.wrap(directives)) do
        {:ok, enq_state} ->
          enq_state

        {:error, :queue_overflow} ->
          Logger.warning("AgentServer #{state.id} queue overflow during strategy init")
          state
      end
    else
      state
    end
  end

  defp build_signal_router(%State{} = state) do
    %{state | signal_router: SignalRouter.build(state)}
  end

  @impl true
  def handle_call({:signal, %Signal{} = signal}, _from, state) do
    result = process_call_signal_with_trace(signal, state)

    case apply_call_signal_result(result, state) do
      {:ok, transformed_agent, new_state} ->
        {:reply, {:ok, transformed_agent}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call({:set_debug, enabled}, _from, %State{} = state) do
    new_state = State.set_debug(state, enabled)
    {:reply, :ok, new_state}
  end

  def handle_call({:recent_events, _opts}, _from, %State{debug: false} = state) do
    {:reply, {:error, :debug_not_enabled}, state}
  end

  def handle_call({:recent_events, opts}, _from, %State{} = state) do
    events = State.get_debug_events(state, opts)
    {:reply, {:ok, events}, state}
  end

  def handle_call({:await_completion, opts}, from, %State{} = state) do
    status_path = Keyword.get(opts, :status_path, [:status])
    result_path = Keyword.get(opts, :result_path, [:last_answer])
    error_path = Keyword.get(opts, :error_path, [:error])
    timeout = Keyword.get(opts, :timeout, RuntimeDefaults.await_timeout())

    case completion_from_agent_state(state.agent.state, status_path, result_path, error_path) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      :pending ->
        {caller_pid, _tag} = from
        monitor_ref = Process.monitor(caller_pid)
        expiry_ref = maybe_schedule_waiter_expiry(timeout, monitor_ref)

        waiter = %{
          from: from,
          monitor_ref: monitor_ref,
          expiry_ref: expiry_ref,
          status_path: status_path,
          result_path: result_path,
          error_path: error_path,
          timeout: timeout
        }

        new_waiters = Map.put(state.completion_waiters, monitor_ref, waiter)
        {:noreply, %{state | completion_waiters: new_waiters}}
    end
  end

  def handle_call({:attach, owner_pid}, _from, state) do
    case state.lifecycle.mod.handle_event({:attach, owner_pid}, state) do
      {:cont, new_state} -> {:reply, :ok, new_state}
      {:stop, reason, new_state} -> {:stop, reason, :ok, new_state}
    end
  end

  def handle_call({:detach, owner_pid}, _from, state) do
    case state.lifecycle.mod.handle_event({:detach, owner_pid}, state) do
      {:cont, new_state} -> {:reply, :ok, new_state}
      {:stop, reason, new_state} -> {:stop, reason, :ok, new_state}
    end
  end

  def handle_call(_msg, _from, state) do
    {:reply, {:error, :unknown_call}, state}
  end

  @impl true
  def handle_cast(:touch, state) do
    case state.lifecycle.mod.handle_event(:touch, state) do
      {:cont, new_state} -> {:noreply, new_state}
      {:stop, reason, new_state} -> {:stop, reason, new_state}
    end
  end

  def handle_cast({:signal, %Signal{} = signal}, state) do
    handle_signal_async(signal, state)
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:drain, state) do
    case State.dequeue(state) do
      {:empty, s} ->
        {:noreply, State.finish_processing(s)}

      {{:value, {signal, directive}}, s1} ->
        TraceContext.set_from_signal(signal)

        result =
          try do
            exec_directive_with_telemetry(directive, signal, s1)
          after
            TraceContext.clear()
          end

        case result do
          {:ok, s2} ->
            continue_draining(s2)

          {:async, _ref, s2} ->
            continue_draining(s2)

          {:stop, reason, s2} ->
            warn_if_normal_stop(reason, directive, s2)
            {:stop, reason, State.set_status(s2, :stopping)}
        end
    end
  end

  def handle_info({:scheduled_signal, message_ref, %Signal{} = signal}, state)
      when is_reference(message_ref) do
    {_timer_ref, state} = State.pop_scheduled_timer(state, message_ref)
    handle_signal_async(signal, state)
  end

  def handle_info({:scheduled_signal, %Signal{} = signal}, state) do
    handle_signal_async(signal, state)
  end

  def handle_info(:post_init_start_children, state) do
    state = start_plugin_children(state)
    send(self(), :post_init_start_subscriptions)
    {:noreply, state}
  end

  def handle_info(:post_init_start_subscriptions, state) do
    state = start_plugin_subscriptions(state)
    send(self(), :post_init_register_schedules)
    {:noreply, state}
  end

  def handle_info(:post_init_register_schedules, state) do
    state = register_plugin_schedules(state)
    send(self(), :post_init_finalize)
    {:noreply, state}
  end

  def handle_info(:post_init_finalize, state) do
    notify_parent_of_startup(state)
    state = start_drain_if_idle(state)
    state = state.lifecycle.mod.init(state.lifecycle, state)
    {:noreply, State.finish_processing(state)}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.get(state.cron_monitors, ref) do
      job_id when not is_nil(job_id) ->
        new_state = %{
          state
          | cron_monitors: Map.delete(state.cron_monitors, ref),
            cron_jobs: Map.delete(state.cron_jobs, job_id)
        }

        {:noreply, new_state}

      nil ->
        handle_non_cron_down(ref, pid, reason, state)
    end
  end

  def handle_info({:await_expired, monitor_ref}, state) do
    case Map.pop(state.completion_waiters, monitor_ref) do
      {nil, _waiters} ->
        {:noreply, state}

      {waiter, waiters} ->
        Process.demonitor(waiter.monitor_ref, [:flush])

        diagnostic = build_timeout_diagnostic_from_state(state, waiter.timeout)
        GenServer.reply(waiter.from, {:error, {:timeout, diagnostic}})

        {:noreply, %{state | completion_waiters: waiters}}
    end
  end

  def handle_info({:EXIT, pid, reason}, state) do
    cond do
      match?(%{parent: %ParentRef{pid: ^pid}}, state) ->
        handle_parent_down(state, pid, reason)

      linked_child_pid?(state, pid) ->
        handle_child_down(state, pid, reason)

      ancestor_pid?(pid) ->
        {:stop, reason, state}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:timeout, ref, :lifecycle_idle_timeout}, state) do
    if state.lifecycle.idle_timer == ref do
      # Clear the timer so stale messages don't trigger after cancel/reset.
      state =
        %{state | lifecycle: Lifecycle.clear_idle_timer(state.lifecycle)}

      case state.lifecycle.mod.handle_event(:idle_timeout, state) do
        {:cont, state} -> {:noreply, state}
        {:stop, reason, state} -> {:stop, reason, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %Signal{} = signal}, state) do
    handle_signal_async(signal, state)
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp handle_non_cron_down(ref, pid, reason, state) do
    # First check if this is an attachment monitor
    case Map.get(state.lifecycle.attachment_monitors, ref) do
      ^pid ->
        # Attachment process died, delegate to lifecycle
        case state.lifecycle.mod.handle_event({:down, ref, pid}, state) do
          {:cont, state} -> {:noreply, state}
          {:stop, reason, state} -> {:stop, reason, state}
        end

      _ ->
        # Not an attachment, check completion waiters using O(1) map lookup by monitor ref
        {popped_waiter, new_waiters} = Map.pop(state.completion_waiters, ref)
        cancel_waiter_expiry(popped_waiter)
        state = %{state | completion_waiters: new_waiters}

        if state.parent_monitor_ref == ref and match?(%{parent: %ParentRef{pid: ^pid}}, state) do
          handle_parent_down(state, pid, reason)
        else
          handle_child_down(state, pid, reason)
        end
    end
  end

  @impl true
  def terminate(reason, state) do
    reply_shutdown_to_completion_waiters(state.completion_waiters)

    Enum.each(state.scheduled_timers, fn {_message_ref, timer_ref} ->
      Process.cancel_timer(timer_ref)
    end)

    if is_reference(state.parent_monitor_ref) do
      Process.demonitor(state.parent_monitor_ref, [:flush])
    end

    cleanup_tracked_children(state)

    # Delegate to lifecycle module for persistence/hibernation
    state.lifecycle.mod.terminate(reason, state)

    Enum.each(state.cron_monitors, fn {ref, _job_id} ->
      Process.demonitor(ref, [:flush])
    end)

    # Clean up all cron jobs owned by this agent
    Enum.each(state.cron_jobs, fn {_job_id, pid} ->
      if is_pid(pid) do
        Jido.Scheduler.cancel(pid)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Internal: Signal Processing
  # ---------------------------------------------------------------------------

  defp handle_signal_async(%Signal{} = signal, state) do
    case process_signal_with_trace(signal, state) do
      {:ok, new_state, _resolved_action} -> {:noreply, new_state}
      {:error, _reason, new_state} -> {:noreply, new_state}
    end
  end

  defp process_signal_with_trace(%Signal{} = signal, state) do
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      process_signal(traced_signal, state)
    after
      TraceContext.clear()
    end
  end

  defp process_call_signal_with_trace(%Signal{} = signal, state) do
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      process_call_signal(traced_signal, state)
    after
      TraceContext.clear()
    end
  end

  defp process_call_signal(%Signal{} = signal, %State{signal_router: router} = state) do
    metadata = build_signal_metadata(state, signal)

    with_telemetry_span([:jido, :agent_server, :signal], metadata, fn start_time ->
      do_process_call_signal(signal, router, state, start_time, metadata)
    end)
  catch
    kind, reason ->
      error =
        Jido.Error.execution_error(
          "Call signal processing crashed",
          %{kind: kind, reason: inspect(reason)}
        )

      {:error, error, [], signal}
  end

  defp do_process_call_signal(signal, router, state, start_time, metadata) do
    case run_plugin_signal_hooks(signal, state) do
      {:error, error} ->
        emit_telemetry(
          [:jido, :agent_server, :signal, :stop],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{error: error})
        )

        error_directive = %Directive.Error{error: error, context: :plugin_handle_signal}
        {:error, error, [error_directive], signal}

      {:override, action_spec, modified_signal} ->
        effective_signal = modified_signal || signal
        execute_call_action(effective_signal, action_spec, state, start_time, metadata)

      {:continue, modified_signal} ->
        case route_to_actions(router, modified_signal) do
          {:ok, actions} ->
            execute_call_action(modified_signal, actions, state, start_time, metadata)

          {:error, reason} ->
            error =
              Jido.Error.routing_error("No route for signal", %{
                signal_type: modified_signal.type,
                details: %{reason: reason}
              })

            emit_telemetry(
              [:jido, :agent_server, :signal, :stop],
              %{duration: System.monotonic_time() - start_time},
              Map.merge(metadata, %{error: error})
            )

            error_directive = %Directive.Error{error: error, context: :routing}
            {:error, error, [error_directive], modified_signal}
        end
    end
  end

  defp execute_call_action(signal, action_spec, state, start_time, metadata) do
    action_arg =
      case action_spec do
        [single] -> single
        list when is_list(list) -> list
        other -> other
      end

    {agent, directives} = state.agent_module.cmd(state.agent, action_arg)
    directives = List.wrap(directives)

    emit_telemetry(
      [:jido, :agent_server, :signal, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{directive_count: length(directives)})
    )

    {:ok, agent, directives, action_arg, signal}
  end

  defp apply_call_signal_result(
         {:ok, agent, directives, resolved_action, %Signal{} = signal},
         %State{} = state
       ) do
    state =
      State.record_debug_event(state, :signal_received, %{
        type: signal.type,
        id: signal.id
      })

    state =
      state
      |> State.update_agent(agent)
      |> maybe_notify_completion_waiters()

    case State.enqueue_all(state, signal, directives) do
      {:ok, enq_state} ->
        new_state = start_drain_if_idle(enq_state)

        transformed_agent =
          run_plugin_transform_hooks(new_state.agent, resolved_action, signal, new_state)

        {:ok, transformed_agent, new_state}

      {:error, :queue_overflow} ->
        {:error, queue_overflow_error(state, signal, directives), state}
    end
  end

  defp apply_call_signal_result(
         {:error, reason, directives, %Signal{} = signal},
         %State{} = state
       ) do
    state =
      State.record_debug_event(state, :signal_received, %{
        type: signal.type,
        id: signal.id
      })

    new_state =
      case State.enqueue_all(state, signal, directives) do
        {:ok, enq_state} -> start_drain_if_idle(enq_state)
        {:error, :queue_overflow} -> state
      end

    {:error, reason, new_state}
  end

  defp process_signal(%Signal{} = signal, %State{signal_router: router} = state) do
    metadata = build_signal_metadata(state, signal)

    # Record debug event for signal received
    state =
      State.record_debug_event(state, :signal_received, %{
        type: signal.type,
        id: signal.id
      })

    with_telemetry_span([:jido, :agent_server, :signal], metadata, fn start_time ->
      do_process_signal(signal, router, state, start_time, metadata)
    end)
  end

  defp build_signal_metadata(state, signal) do
    trace_metadata = TraceContext.to_telemetry_metadata()

    %{
      agent_id: state.id,
      agent_module: state.agent_module,
      signal_type: signal.type
    }
    |> Map.merge(trace_metadata)
  end

  defp do_process_signal(signal, router, state, start_time, metadata) do
    case run_plugin_signal_hooks(signal, state) do
      {:error, error} ->
        handle_plugin_hook_error(error, signal, state)

      {:override, action_spec, modified_signal} ->
        effective_signal = modified_signal || signal
        dispatch_action(effective_signal, action_spec, state, start_time, metadata)

      {:continue, modified_signal} ->
        handle_signal_routing(modified_signal, router, state, start_time, metadata)
    end
  end

  defp handle_plugin_hook_error(error, signal, state) do
    error_directive = %Directive.Error{error: error, context: :plugin_handle_signal}
    enqueue_error_directive(error, signal, [error_directive], state)
  end

  defp handle_signal_routing(signal, router, state, start_time, metadata) do
    case route_to_actions(router, signal) do
      {:ok, actions} ->
        dispatch_action(signal, actions, state, start_time, metadata)

      {:error, reason} ->
        handle_routing_error(reason, signal, state, start_time, metadata)
    end
  end

  defp handle_routing_error(reason, signal, state, start_time, metadata) do
    error =
      Jido.Error.routing_error("No route for signal", %{
        signal_type: signal.type,
        details: %{reason: reason}
      })

    emit_telemetry(
      [:jido, :agent_server, :signal, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{error: error})
    )

    error_directive = %Directive.Error{error: error, context: :routing}
    enqueue_error_directive(error, signal, [error_directive], state)
  end

  defp enqueue_error_directive(error, signal, directives, state) do
    case State.enqueue_all(state, signal, directives) do
      {:ok, enq_state} -> {:error, error, start_drain_if_idle(enq_state)}
      {:error, :queue_overflow} -> {:error, error, state}
    end
  end

  defp dispatch_action(signal, action_spec, state, start_time, metadata) do
    agent_module = state.agent_module

    action_arg =
      case action_spec do
        [single] -> single
        list when is_list(list) -> list
        other -> other
      end

    {agent, directives} = agent_module.cmd(state.agent, action_arg)

    directives = List.wrap(directives)
    state = State.update_agent(state, agent)
    state = maybe_notify_completion_waiters(state)

    emit_telemetry(
      [:jido, :agent_server, :signal, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{directive_count: length(directives)})
    )

    case State.enqueue_all(state, signal, directives) do
      {:ok, enq_state} ->
        {:ok, start_drain_if_idle(enq_state), action_arg}

      {:error, :queue_overflow} ->
        emit_telemetry(
          [:jido, :agent_server, :queue, :overflow],
          %{queue_size: state.max_queue_size},
          metadata
        )

        Logger.warning("AgentServer #{state.id} queue overflow, dropping directives")
        {:error, :queue_overflow, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Signal Routing
  # ---------------------------------------------------------------------------

  defp route_to_actions(router, signal) do
    case JidoRouter.route(router, signal) do
      {:ok, targets} when targets != [] ->
        actions = Enum.map(targets, &target_to_action(&1, signal))
        {:ok, actions}

      {:error, %{details: %{reason: :no_handlers_found}}} ->
        {:error, :no_matching_route}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp target_to_action({:strategy_cmd, cmd}, %Signal{data: data}) do
    {cmd, data}
  end

  defp target_to_action({:strategy_tick}, _signal) do
    {:strategy_tick, %{}}
  end

  defp target_to_action({:custom, _term}, %Signal{data: data}) do
    {:custom, data}
  end

  defp target_to_action(mod, %Signal{data: data}) when is_atom(mod) do
    {mod, data}
  end

  defp target_to_action({mod, params}, _signal) when is_atom(mod) and is_map(params) do
    {mod, params}
  end

  # ---------------------------------------------------------------------------
  # Internal: Plugin Signal Hooks
  # ---------------------------------------------------------------------------

  defp run_plugin_signal_hooks(%Signal{} = signal, %State{} = state) do
    agent_module = state.agent_module

    specs_and_instances = get_plugin_specs_and_instances(agent_module)

    Enum.reduce_while(specs_and_instances, {:continue, signal}, fn {spec, instance},
                                                                   {_, current_signal} ->
      run_single_plugin_signal_hook(
        spec,
        instance,
        current_signal,
        state,
        agent_module
      )
    end)
    |> normalize_hook_result()
  end

  defp run_single_plugin_signal_hook(spec, instance, current_signal, state, agent_module) do
    if signal_matches_plugin?(current_signal, spec) do
      case invoke_plugin_handle_signal(instance, spec, current_signal, state, agent_module) do
        {:cont, :continue} ->
          {:cont, {:continue, current_signal}}

        {:cont, {:continue, new_signal}} ->
          {:cont, {:continue, new_signal}}

        {:halt, {:override, action_spec}} ->
          {:halt, {:override, action_spec}}

        {:halt, {:override, action_spec, new_signal}} ->
          {:halt, {:override, action_spec, new_signal}}

        {:halt, {:error, error}} ->
          {:halt, {:error, error}}
      end
    else
      {:cont, {:continue, current_signal}}
    end
  end

  defp normalize_hook_result({:continue, signal}), do: {:continue, signal}
  defp normalize_hook_result({:override, action_spec}), do: {:override, action_spec, nil}

  defp normalize_hook_result({:override, action_spec, signal}),
    do: {:override, action_spec, signal}

  defp normalize_hook_result({:error, error}), do: {:error, error}

  defp signal_matches_plugin?(_signal, %{signal_patterns: []}), do: true
  defp signal_matches_plugin?(_signal, %{signal_patterns: nil}), do: true

  defp signal_matches_plugin?(%Signal{type: type}, %{signal_patterns: patterns}) do
    Enum.any?(patterns, &signal_type_matches?(type, &1))
  end

  defp signal_type_matches?(type, pattern) do
    cond do
      pattern == type ->
        true

      String.ends_with?(pattern, ".*") ->
        prefix = String.trim_trailing(pattern, ".*")
        String.starts_with?(type, prefix <> ".")

      String.contains?(pattern, "*") ->
        pattern_regex =
          pattern
          |> Regex.escape()
          |> String.replace("\\*", "[^.]*")

        Regex.match?(~r/^#{pattern_regex}$/, type)

      true ->
        false
    end
  end

  defp get_plugin_specs_and_instances(agent_module) do
    specs =
      if function_exported?(agent_module, :plugin_specs, 0),
        do: agent_module.plugin_specs(),
        else: []

    instances =
      if function_exported?(agent_module, :plugin_instances, 0),
        do: agent_module.plugin_instances(),
        else: []

    Enum.zip(specs, instances)
  end

  defp invoke_plugin_handle_signal(instance, spec, signal, state, agent_module) do
    context = %{
      agent: state.agent,
      agent_module: agent_module,
      plugin: spec.module,
      plugin_spec: spec,
      plugin_instance: instance,
      config: spec.config || %{}
    }

    case run_plugin_callback_with_timeout(state, spec.module, :handle_signal, fn ->
           spec.module.handle_signal(signal, context)
         end) do
      {:ok, {:ok, {:override, action_spec}}} ->
        {:halt, {:override, action_spec}}

      {:ok, {:ok, {:continue, %Signal{} = new_signal}}} ->
        {:cont, {:continue, new_signal}}

      {:ok, {:ok, {:override, action_spec, %Signal{} = new_signal}}} ->
        {:halt, {:override, action_spec, new_signal}}

      {:ok, {:ok, _}} ->
        {:cont, :continue}

      {:ok, {:error, reason}} ->
        error =
          Jido.Error.execution_error(
            "Plugin handle_signal failed",
            %{plugin: spec.module, reason: reason}
          )

        {:halt, {:error, error}}

      {:error, {:timeout, timeout_ms}} ->
        error =
          Jido.Error.timeout_error(
            "Plugin handle_signal timed out",
            %{plugin: spec.module, timeout_ms: timeout_ms}
          )

        {:halt, {:error, error}}

      {:error, {:exit, reason}} ->
        Logger.error("Plugin #{inspect(spec.module)} handle_signal crashed: #{inspect(reason)}")

        error =
          Jido.Error.execution_error(
            "Plugin handle_signal crashed",
            %{plugin: spec.module, exception: inspect(reason)}
          )

        {:halt, {:error, error}}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Plugin Transform Hooks
  # ---------------------------------------------------------------------------

  defp run_plugin_transform_hooks(agent, resolved_action, original_signal, %State{} = state) do
    agent_module = state.agent_module

    specs_and_instances = get_plugin_specs_and_instances(agent_module)

    action_term = normalize_action_for_transform(resolved_action, original_signal)

    Enum.reduce(specs_and_instances, agent, fn {spec, instance}, agent_acc ->
      context = %{
        agent: agent_acc,
        agent_module: agent_module,
        plugin: spec.module,
        plugin_spec: spec,
        plugin_instance: instance,
        config: spec.config || %{}
      }

      run_transform_hook(state, spec, action_term, context, agent_acc)
    end)
  end

  defp run_transform_hook(state, spec, action_term, context, agent_acc) do
    case run_plugin_callback_with_timeout(state, spec.module, :transform_result, fn ->
           spec.module.transform_result(action_term, agent_acc, context)
         end) do
      {:ok, transformed_agent} ->
        transformed_agent

      {:error, {:timeout, timeout_ms}} ->
        Logger.error(
          "Plugin #{inspect(spec.module)} transform_result timed out after #{timeout_ms}ms"
        )

        agent_acc

      {:error, {:exit, reason}} ->
        Logger.error(
          "Plugin #{inspect(spec.module)} transform_result crashed: #{inspect(reason)}"
        )

        agent_acc
    end
  end

  defp normalize_action_for_transform(resolved_action, original_signal) do
    case resolved_action do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      {mod, _params} when is_atom(mod) -> mod
      [{mod, _params} | _] when is_atom(mod) -> mod
      [mod | _] when is_atom(mod) -> mod
      _ -> original_signal.type
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Plugin Children
  # ---------------------------------------------------------------------------

  @doc false
  defp start_plugin_children(%State{} = state) do
    agent_module = state.agent_module

    plugin_specs =
      if function_exported?(agent_module, :plugin_specs, 0),
        do: agent_module.plugin_specs(),
        else: []

    Enum.reduce(plugin_specs, state, fn spec, acc_state ->
      config = spec.config || %{}
      safe_start_plugin_spec_children(acc_state, spec.module, config)
    end)
  end

  defp safe_start_plugin_spec_children(%State{} = state, plugin_module, config) do
    start_plugin_spec_children(state, plugin_module, config)
  rescue
    error ->
      Logger.error(
        "Plugin #{inspect(plugin_module)} child_spec startup crashed: #{Exception.message(error)}"
      )

      state
  catch
    kind, reason ->
      Logger.error(
        "Plugin #{inspect(plugin_module)} child_spec startup #{kind}: #{inspect(reason)}"
      )

      state
  end

  defp start_plugin_spec_children(state, plugin_module, config) do
    case plugin_module.child_spec(config) do
      nil ->
        state

      %{} = child_spec ->
        start_plugin_child(state, plugin_module, child_spec)

      list when is_list(list) ->
        Enum.reduce(list, state, fn cs, s ->
          start_plugin_child(s, plugin_module, cs)
        end)

      other ->
        Logger.warning(
          "Invalid child_spec from plugin #{inspect(plugin_module)}: #{inspect(other)}"
        )

        state
    end
  end

  defp start_plugin_child(%State{} = state, plugin_module, %{start: {m, _f, _a}} = spec) do
    child_spec = supervised_runtime_child_spec(spec)

    case start_runtime_child(state, child_spec) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        tag = {:plugin, plugin_module, spec[:id] || m}

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: plugin_module,
            id: "#{plugin_module}-#{inspect(pid)}",
            tag: tag,
            meta: %{child_spec_id: spec[:id]}
          })

        new_children = Map.put(state.children, tag, child_info)
        %{state | children: new_children}

      {:ok, pid, _info} ->
        ref = Process.monitor(pid)
        tag = {:plugin, plugin_module, spec[:id] || m}

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: plugin_module,
            id: "#{plugin_module}-#{inspect(pid)}",
            tag: tag,
            meta: %{child_spec_id: spec[:id]}
          })

        new_children = Map.put(state.children, tag, child_info)
        %{state | children: new_children}

      {:error, reason} ->
        Logger.error("Failed to start plugin child #{inspect(plugin_module)}: #{inspect(reason)}")

        state
    end
  end

  defp start_plugin_child(%State{} = state, plugin_module, spec) do
    Logger.warning(
      "Plugin child_spec missing :start key for #{inspect(plugin_module)}: #{inspect(spec)}"
    )

    state
  end

  # ---------------------------------------------------------------------------
  # Internal: Plugin Subscriptions
  # ---------------------------------------------------------------------------

  @doc false
  defp start_plugin_subscriptions(%State{} = state) do
    agent_module = state.agent_module

    plugin_specs =
      if function_exported?(agent_module, :plugin_specs, 0),
        do: agent_module.plugin_specs(),
        else: []

    Enum.reduce(plugin_specs, state, fn spec, acc_state ->
      safe_start_plugin_subscriptions(acc_state, agent_module, spec)
    end)
  end

  defp safe_start_plugin_subscriptions(%State{} = state, agent_module, spec) do
    context = %{
      agent_ref: via_tuple(state.id, state.registry),
      agent_id: state.id,
      agent_module: agent_module,
      plugin_spec: spec,
      jido_instance: state.jido
    }

    config = spec.config || %{}

    subscriptions =
      if function_exported?(spec.module, :subscriptions, 2),
        do: spec.module.subscriptions(config, context),
        else: []

    Enum.reduce(subscriptions, state, fn {sensor_module, sensor_config}, acc_state ->
      start_subscription_sensor(acc_state, spec.module, sensor_module, sensor_config, context)
    end)
  rescue
    error ->
      Logger.warning(
        "Plugin #{inspect(spec.module)} subscriptions startup crashed: #{Exception.message(error)}"
      )

      state
  catch
    kind, reason ->
      Logger.warning(
        "Plugin #{inspect(spec.module)} subscriptions startup #{kind}: #{inspect(reason)}"
      )

      state
  end

  defp start_subscription_sensor(
         %State{} = state,
         plugin_module,
         sensor_module,
         sensor_config,
         context
       ) do
    opts = [
      sensor: sensor_module,
      config: sensor_config,
      context: context
    ]

    child_spec = supervised_runtime_child_spec({SensorRuntime, opts})

    case start_runtime_child(state, child_spec) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        tag = {:sensor, plugin_module, sensor_module}

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: sensor_module,
            id: "#{plugin_module}-#{sensor_module}-#{inspect(pid)}",
            tag: tag,
            meta: %{plugin: plugin_module, sensor: sensor_module}
          })

        new_children = Map.put(state.children, tag, child_info)
        %{state | children: new_children}

      {:ok, pid, _info} ->
        ref = Process.monitor(pid)
        tag = {:sensor, plugin_module, sensor_module}

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: sensor_module,
            id: "#{plugin_module}-#{sensor_module}-#{inspect(pid)}",
            tag: tag,
            meta: %{plugin: plugin_module, sensor: sensor_module}
          })

        new_children = Map.put(state.children, tag, child_info)
        %{state | children: new_children}

      {:error, reason} ->
        Logger.warning(
          "Failed to start subscription sensor #{inspect(sensor_module)} for plugin #{inspect(plugin_module)}: #{inspect(reason)}"
        )

        state
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Plugin Schedules
  # ---------------------------------------------------------------------------

  @doc false
  defp register_plugin_schedules(%State{skip_schedules: true} = state) do
    Logger.debug("AgentServer #{state.id} skipping plugin schedules")
    state
  end

  defp register_plugin_schedules(%State{} = state) do
    agent_module = state.agent_module

    schedules =
      if function_exported?(agent_module, :plugin_schedules, 0),
        do: agent_module.plugin_schedules(),
        else: []

    Enum.reduce(schedules, state, fn schedule_spec, acc_state ->
      safe_register_schedule(acc_state, schedule_spec)
    end)
  end

  defp safe_register_schedule(%State{} = state, schedule_spec) do
    register_schedule(state, schedule_spec)
  rescue
    error ->
      Logger.error("Failed to register plugin schedule: #{Exception.message(error)}")
      state
  catch
    kind, reason ->
      Logger.error("Failed to register plugin schedule (#{kind}): #{inspect(reason)}")
      state
  end

  defp register_schedule(%State{} = state, schedule_spec) do
    %{
      cron_expression: cron_expr,
      action: _action,
      job_id: job_id,
      signal_type: signal_type,
      timezone: timezone
    } = schedule_spec

    agent_id = state.id
    agent_ref = via_tuple(agent_id, state.registry)

    signal = Signal.new!(signal_type, %{}, source: "/agent/#{agent_id}/schedule")

    opts = if timezone, do: [timezone: timezone], else: []

    result =
      Jido.Scheduler.run_every(
        fn ->
          case cast(agent_ref, signal) do
            :ok ->
              :ok

            {:error, reason} ->
              Logger.warning(
                "AgentServer #{agent_id} failed to deliver schedule #{inspect(job_id)} tick: #{inspect(reason)}"
              )

              :ok
          end

          :ok
        end,
        cron_expr,
        opts
      )

    case result do
      {:ok, pid} ->
        Logger.debug(
          "AgentServer #{agent_id} registered schedule #{inspect(job_id)}: #{cron_expr}"
        )

        {cron_jobs, cron_monitors} = track_cron_job(state, job_id, pid)
        %{state | cron_jobs: cron_jobs, cron_monitors: cron_monitors}

      {:error, reason} ->
        Logger.error(
          "AgentServer #{agent_id} failed to register schedule #{inspect(job_id)}: #{inspect(reason)}"
        )

        state
    end
  end

  defp track_cron_job(%State{} = state, job_id, pid) when is_pid(pid) do
    {existing_pid, cron_jobs} = Map.pop(state.cron_jobs, job_id)

    if is_pid(existing_pid) and existing_pid != pid do
      Jido.Scheduler.cancel(existing_pid)
    end

    {existing_ref, cron_monitors} =
      Enum.find(state.cron_monitors, fn {_ref, existing_job_id} -> existing_job_id == job_id end)
      |> case do
        {ref, _} -> {ref, Map.delete(state.cron_monitors, ref)}
        nil -> {nil, state.cron_monitors}
      end

    if is_reference(existing_ref) do
      Process.demonitor(existing_ref, [:flush])
    end

    ref = Process.monitor(pid)
    {Map.put(cron_jobs, job_id, pid), Map.put(cron_monitors, ref, job_id)}
  end

  # ---------------------------------------------------------------------------
  # Internal: Drain Loop
  # ---------------------------------------------------------------------------

  defp start_drain_if_idle(%State{processing: false} = state) do
    send(self(), :drain)
    State.start_processing(state)
  end

  defp start_drain_if_idle(%State{} = state), do: state

  defp continue_draining(state) do
    if State.queue_empty?(state) do
      {:noreply, State.finish_processing(state)}
    else
      send(self(), :drain)
      {:noreply, State.start_processing(state)}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Completion Detection
  # ---------------------------------------------------------------------------

  defp completion_from_agent_state(agent_state, status_path, result_path, error_path) do
    case get_in(agent_state, status_path) do
      :completed ->
        {:ok, %{status: :completed, result: get_in(agent_state, result_path)}}

      :failed ->
        {:ok, %{status: :failed, result: get_in(agent_state, error_path)}}

      _ ->
        :pending
    end
  end

  defp maybe_notify_completion_waiters(%State{completion_waiters: waiters} = state)
       when map_size(waiters) == 0 do
    state
  end

  defp maybe_notify_completion_waiters(%State{completion_waiters: waiters, agent: agent} = state) do
    {to_notify, still_waiting} =
      Enum.split_with(waiters, fn {_ref, waiter} ->
        completion_from_agent_state(
          agent.state,
          waiter.status_path,
          waiter.result_path,
          waiter.error_path
        ) != :pending
      end)

    Enum.each(to_notify, fn {_ref, waiter} ->
      {:ok, result} =
        completion_from_agent_state(
          agent.state,
          waiter.status_path,
          waiter.result_path,
          waiter.error_path
        )

      cancel_waiter_expiry(waiter)
      Process.demonitor(waiter.monitor_ref, [:flush])
      GenServer.reply(waiter.from, {:ok, result})
    end)

    %{state | completion_waiters: Map.new(still_waiting)}
  end

  defp maybe_schedule_waiter_expiry(timeout, monitor_ref)
       when is_integer(timeout) and timeout > 0 do
    Process.send_after(self(), {:await_expired, monitor_ref}, timeout)
  end

  defp maybe_schedule_waiter_expiry(_timeout, _monitor_ref), do: nil

  defp cancel_waiter_expiry(%{expiry_ref: expiry_ref}) when is_reference(expiry_ref) do
    Process.cancel_timer(expiry_ref)
    :ok
  end

  defp cancel_waiter_expiry(_), do: :ok

  defp build_timeout_diagnostic_from_state(%State{} = state, timeout_ms) do
    snapshot = state.agent_module.strategy_snapshot(state.agent)

    %{
      waited_ms: timeout_ms,
      server_status: snapshot.status,
      queue_length: State.queue_length(state),
      iteration: Map.get(snapshot, :iteration),
      hint: infer_timeout_hint(snapshot.status)
    }
  end

  # ---------------------------------------------------------------------------
  # Internal: Agent Resolution
  # ---------------------------------------------------------------------------

  defp resolve_agent(%Options{
         agent: agent,
         agent_module: explicit_module,
         initial_state: init_state,
         id: id
       }) do
    cond do
      is_atom(agent) ->
        cond do
          function_exported?(agent, :new, 1) ->
            # new/1 accepts keyword options like [id: ..., state: ...]
            {:ok, agent, agent.new(id: id, state: init_state)}

          function_exported?(agent, :new, 0) ->
            {:ok, agent, agent.new()}

          true ->
            {:error, Jido.Error.validation_error("Agent module must implement new/0 or new/1")}
        end

      is_struct(agent) ->
        # For pre-built agents, use explicit agent_module if provided
        # Otherwise fall back to the struct module (may not work for Jido.Agent structs)
        agent_module = explicit_module || agent.__struct__
        {:ok, agent_module, agent}

      true ->
        {:error, Jido.Error.validation_error("Invalid agent")}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Server Resolution
  # ---------------------------------------------------------------------------

  defp resolve_server(pid) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :not_found}
  end

  defp resolve_server({:via, _, _} = via) do
    case safe_whereis(via) do
      nil -> {:error, :not_found}
      _pid -> {:ok, via}
    end
  end

  defp resolve_server(name) when is_atom(name) do
    case safe_whereis(name) do
      nil -> {:error, :not_found}
      _pid -> {:ok, name}
    end
  end

  defp resolve_server(id) when is_binary(id) do
    # String IDs require explicit registry lookup via Jido.whereis/2
    {:error,
     {:invalid_server,
      "String IDs require explicit registry lookup. Use Jido.whereis(MyApp.Jido, \"#{id}\") first or pass the pid directly."}}
  end

  defp resolve_server(_), do: {:error, :invalid_server}

  defp safe_whereis(server_ref) do
    GenServer.whereis(server_ref)
  rescue
    ArgumentError -> nil
  catch
    :exit, _ -> nil
  end

  defp safe_registry_lookup(registry, id) do
    Registry.lookup(registry, id)
  rescue
    ArgumentError -> []
  end

  # ---------------------------------------------------------------------------
  # Internal: Hierarchy
  # ---------------------------------------------------------------------------

  defp maybe_monitor_parent(%State{parent: %ParentRef{pid: pid}} = state) when is_pid(pid) do
    parent_monitor_ref = Process.monitor(pid)
    %{state | parent_monitor_ref: parent_monitor_ref}
  end

  defp maybe_monitor_parent(state), do: state

  defp runtime_child_supervisor_name(%State{jido: jido}) when is_atom(jido),
    do: Jido.agent_supervisor_name(jido)

  defp runtime_child_supervisor_name(_state), do: Jido.AgentSupervisor

  defp supervised_runtime_child_spec(spec) do
    Supervisor.child_spec(spec, [])
  end

  defp start_runtime_child(%State{} = state, child_spec) do
    supervisor = runtime_child_supervisor_name(state)

    case maybe_whereis_supervisor(supervisor) do
      {:ok, _pid} ->
        case safe_dynamic_supervisor_start_child(supervisor, child_spec) do
          {:error, :not_found} -> {:error, :missing_supervisor}
          other -> other
        end

      {:error, :not_found} ->
        {:error, :missing_supervisor}
    end
  end

  defp notify_parent_of_startup(%State{parent: %ParentRef{} = parent} = state)
       when is_pid(parent.pid) do
    child_started =
      ChildStarted.new!(
        %{
          parent_id: parent.id,
          child_id: state.id,
          child_module: state.agent_module,
          tag: parent.tag,
          pid: self(),
          meta: parent.meta || %{}
        },
        source: "/agent/#{state.id}"
      )

    _ = cast(parent.pid, ensure_traced_signal(child_started))
    :ok
  end

  defp notify_parent_of_startup(_state), do: :ok

  defp handle_parent_down(%State{on_parent_death: :stop} = state, _pid, reason) do
    Logger.info("AgentServer #{state.id} stopping: parent died (#{inspect(reason)})")
    # Wrap the stop reason so OTP treats it as a clean shutdown (no error logs).
    # OTP considers :normal, :shutdown, and {:shutdown, term} as "normal" exits.
    # Benign reasons: :normal (parent stopped normally), :noproc (parent already gone),
    # :shutdown (parent shutting down), {:shutdown, _} (parent shutdown with reason).
    stop_reason = wrap_parent_down_reason(reason)
    {:stop, stop_reason, State.set_status(state, :stopping)}
  end

  defp handle_parent_down(%State{on_parent_death: :continue} = state, _pid, reason) do
    Logger.info("AgentServer #{state.id} continuing after parent death (#{inspect(reason)})")
    {:noreply, state}
  end

  defp handle_parent_down(%State{on_parent_death: :emit_orphan} = state, _pid, reason) do
    signal =
      Orphaned.new!(
        %{parent_id: state.parent.id, reason: reason},
        source: "/agent/#{state.id}"
      )

    case process_signal(ensure_traced_signal(signal), state) do
      {:ok, new_state, _resolved_action} -> {:noreply, new_state}
      {:error, _reason, ns} -> {:noreply, ns}
    end
  end

  defp handle_child_down(%State{} = state, pid, reason) do
    {tag, state} = State.remove_child_by_pid(state, pid)

    if tag do
      Logger.debug("AgentServer #{state.id} child #{inspect(tag)} exited: #{inspect(reason)}")

      signal =
        ChildExit.new!(
          %{tag: tag, pid: pid, reason: reason},
          source: "/agent/#{state.id}"
        )

      case process_signal(ensure_traced_signal(signal), state) do
        {:ok, new_state, _resolved_action} -> {:noreply, new_state}
        {:error, _reason, ns} -> {:noreply, ns}
      end
    else
      {:noreply, state}
    end
  end

  # Wraps parent-down reasons so OTP treats them as clean shutdowns.
  # OTP only considers :normal, :shutdown, and {:shutdown, term} as "normal" exits.
  # All other reasons get logged as errors by the default GenServer logger.
  defp wrap_parent_down_reason(:normal), do: {:shutdown, {:parent_down, :normal}}
  defp wrap_parent_down_reason(:noproc), do: {:shutdown, {:parent_down, :noproc}}
  defp wrap_parent_down_reason(:shutdown), do: {:shutdown, {:parent_down, :shutdown}}
  defp wrap_parent_down_reason({:shutdown, _} = r), do: {:shutdown, {:parent_down, r}}
  defp wrap_parent_down_reason(reason), do: {:parent_down, reason}

  defp linked_child_pid?(%State{children: children}, pid) when is_pid(pid) do
    Enum.any?(children, fn {_tag, child} -> child.pid == pid end)
  end

  defp ancestor_pid?(pid) when is_pid(pid) do
    case Process.get(:"$ancestors") do
      ancestors when is_list(ancestors) -> pid in ancestors
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Telemetry
  # ---------------------------------------------------------------------------

  defp exec_directive_with_telemetry(directive, signal, state) do
    directive_type =
      directive.__struct__ |> Module.split() |> List.last()

    # Record debug event for directive execution
    state =
      State.record_debug_event(state, :directive_started, %{
        type: directive_type,
        signal_type: signal.type
      })

    trace_metadata = TraceContext.to_telemetry_metadata()

    metadata =
      %{
        agent_id: state.id,
        agent_module: state.agent_module,
        directive_type: directive_type,
        signal_type: signal.type
      }
      |> Map.merge(trace_metadata)

    with_telemetry_span([:jido, :agent_server, :directive], metadata, fn start_time ->
      result = DirectiveExec.exec(directive, signal, state)

      emit_telemetry(
        [:jido, :agent_server, :directive, :stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, %{result: result_type(result)})
      )

      result
    end)
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:async, _, _}), do: :async
  defp result_type({:stop, _, _}), do: :stop

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  end

  defp with_telemetry_span(event_prefix, metadata, fun) when is_list(event_prefix) do
    start_time = System.monotonic_time()

    emit_telemetry(
      event_prefix ++ [:start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      fun.(start_time)
    catch
      kind, reason ->
        emit_telemetry(
          event_prefix ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  # Warn when {:stop, ...} is used with normal-looking reasons.
  # This indicates likely misuse - normal completion should use state.status instead.
  defp warn_if_normal_stop(reason, directive, state)
       when reason in [:normal, :completed, :ok, :done, :success] do
    directive_type = directive.__struct__ |> Module.split() |> List.last()

    Logger.warning("""
    AgentServer #{state.id} received {:stop, #{inspect(reason)}, ...} from directive #{directive_type}.

    This is a HARD STOP: pending directives and async work will be lost, and on_after_cmd/3 will NOT run.

    For normal completion, set state.status to :completed/:failed instead and avoid returning {:stop, ...}.
    External code should poll AgentServer.state/1 and check status, not rely on process death.

    {:stop, ...} should only be used for abnormal/framework-level termination.
    """)
  end

  defp warn_if_normal_stop(_reason, _directive, _state), do: :ok

  defp safe_call(server_ref, request, timeout \\ RuntimeDefaults.agent_server_call_timeout()) do
    GenServer.call(server_ref, request, timeout)
  catch
    :exit, {:noproc, _} ->
      {:error, :not_found}

    :exit, {:normal, _} ->
      {:error, :not_found}

    :exit, {:shutdown, _} ->
      {:error, :not_found}

    :exit, :shutdown ->
      {:error, :not_found}

    :exit, {:timeout, _} ->
      {:error, :timeout}
  end

  defp safe_cast(server_ref, message) do
    GenServer.cast(server_ref, message)
    :ok
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
    :exit, {:shutdown, _} -> {:error, :not_found}
    :exit, :shutdown -> {:error, :not_found}
  end

  defp reply_shutdown_to_completion_waiters(waiters) do
    Enum.each(waiters, fn {_ref, waiter} ->
      cancel_waiter_expiry(waiter)
      Process.demonitor(waiter.monitor_ref, [:flush])
      GenServer.reply(waiter.from, {:error, :shutdown})
    end)
  end

  defp stream_status_error(:halt, _reason), do: {:halt, :halt}
  defp stream_status_error(:emit, reason), do: {[{:error, reason}], :halt}

  defp stream_status_error(_on_error, reason) do
    raise "Failed to get status: #{inspect(reason)}"
  end

  defp cleanup_tracked_children(%State{} = state) do
    Enum.each(state.children, fn {_tag, child} ->
      if is_reference(child.ref) do
        Process.demonitor(child.ref, [:flush])
      end

      unless skip_child_cleanup?(child) do
        maybe_stop_tracked_child(state, child.pid)
      end
    end)
  end

  defp skip_child_cleanup?(%ChildInfo{meta: %{directive: :spawn_agent}}), do: true
  defp skip_child_cleanup?(_child), do: false

  defp maybe_stop_tracked_child(_state, pid) when not is_pid(pid), do: :ok

  defp maybe_stop_tracked_child(%State{} = state, pid) do
    supervisor = runtime_child_supervisor_name(state)

    case maybe_whereis_supervisor(supervisor) do
      {:ok, _sup_pid} ->
        case safe_dynamic_supervisor_terminate_child(supervisor, pid) do
          :ok -> :ok
          {:error, :not_found} -> safe_process_exit(pid, :shutdown)
        end

      {:error, :not_found} ->
        safe_process_exit(pid, :shutdown)
    end
  end

  defp safe_process_exit(pid, reason) when is_pid(pid) do
    Process.exit(pid, reason)
    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp run_plugin_callback_with_timeout(%State{jido: jido}, plugin, callback, fun)
       when is_function(fun, 0) do
    timeout_ms = RuntimeDefaults.plugin_hook_timeout()

    case Tasking.resolve_task_supervisor(jido: jido) do
      {:ok, task_supervisor} ->
        run_plugin_callback_task(task_supervisor, plugin, callback, timeout_ms, fun)

      {:error, :task_supervisor_not_found} ->
        # Fallback path for bootstrap/runtime edge cases.
        {:ok, fun.()}
    end
  end

  defp run_plugin_callback_task(task_supervisor, plugin, callback, timeout_ms, fun)
       when is_atom(task_supervisor) and is_integer(timeout_ms) and is_function(fun, 0) do
    parent = self()
    result_ref = make_ref()

    case Task.Supervisor.start_child(task_supervisor, fn ->
           send(parent, {:plugin_hook_result, result_ref, fun.()})
         end) do
      {:ok, pid} ->
        await_plugin_callback_result(pid, result_ref, plugin, callback, timeout_ms)

      {:error, reason} ->
        {:error, {:exit, reason}}
    end
  end

  defp await_plugin_callback_result(pid, result_ref, plugin, callback, timeout_ms)
       when is_pid(pid) and is_reference(result_ref) and is_integer(timeout_ms) do
    monitor_ref = Process.monitor(pid)

    receive do
      {:plugin_hook_result, ^result_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        {:ok, result}

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        {:error, {:exit, reason}}
    after
      timeout_ms ->
        Process.demonitor(monitor_ref, [:flush])
        Process.exit(pid, :kill)
        flush_plugin_result(result_ref)

        Logger.warning("Plugin #{inspect(plugin)} #{callback} timed out after #{timeout_ms}ms")

        {:error, {:timeout, timeout_ms}}
    end
  end

  defp flush_plugin_result(result_ref) do
    receive do
      {:plugin_hook_result, ^result_ref, _result} -> :ok
    after
      0 -> :ok
    end
  end

  defp queue_overflow_error(state, %Signal{} = signal, directives) do
    Jido.Error.execution_error(
      "Directive queue overflow",
      details: %{
        reason: :queue_overflow,
        signal_type: signal.type,
        max_queue_size: state.max_queue_size,
        directive_count: length(List.wrap(directives))
      }
    )
  end

  defp maybe_whereis_supervisor(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :not_found}
    end
  end

  defp safe_dynamic_supervisor_start_child(supervisor, child_spec) when is_atom(supervisor) do
    DynamicSupervisor.start_child(supervisor, child_spec)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
    :exit, {:shutdown, _} -> {:error, :not_found}
  end

  defp safe_dynamic_supervisor_terminate_child(supervisor, pid) when is_atom(supervisor) do
    DynamicSupervisor.terminate_child(supervisor, pid)
  catch
    :exit, {:noproc, _} -> {:error, :not_found}
    :exit, {:normal, _} -> {:error, :not_found}
    :exit, {:shutdown, _} -> {:error, :not_found}
  end

  defp normalize_status_pid(pid) when is_pid(pid), do: pid

  defp normalize_status_pid(server_ref) do
    safe_whereis(server_ref)
  end

  defp ensure_traced_signal(%Signal{} = signal) do
    case Trace.put(signal, Trace.new_root()) do
      {:ok, traced_signal} -> traced_signal
      {:error, _} -> signal
    end
  end
end
