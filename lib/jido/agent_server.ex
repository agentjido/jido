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
        waited_ms: 5000
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
  alias Jido.Sensor.Runtime, as: SensorRuntime
  alias Jido.Signal
  alias Jido.Signal.Router, as: JidoRouter
  alias Jido.Tracing.Context, as: TraceContext
  alias Jido.Tracing.Trace

  @type server :: pid() | atom() | {:via, module(), term()} | String.t()

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
    child_spec = {__MODULE__, opts}

    jido_instance =
      if is_list(opts), do: Keyword.get(opts, :jido), else: Map.get(opts, :jido)

    supervisor =
      case jido_instance do
        nil -> Jido.AgentSupervisor
        instance -> Jido.agent_supervisor_name(instance)
      end

    DynamicSupervisor.start_child(supervisor, child_spec)
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
      shutdown: 5_000,
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
      {:ok, agent} = Jido.AgentServer.call("agent-id", signal, 10_000)
  """
  @spec call(server(), Signal.t(), timeout()) :: {:ok, struct()} | {:error, term()}
  def call(server, %Signal{} = signal, timeout \\ 5_000) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, {:signal, signal}, timeout)
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
      :ok = Jido.AgentServer.cast("agent-id", signal)
  """
  @spec cast(server(), Signal.t()) :: :ok | {:error, term()}
  def cast(server, %Signal{} = signal) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.cast(pid, {:signal, signal})
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
      {:ok, state} = Jido.AgentServer.state("agent-id")
  """
  @spec state(server()) :: {:ok, State.t()} | {:error, term()}
  def state(server) do
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, :get_state)
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
  - Exits with `{:timeout, ...}` if GenServer.call times out

  ## Examples

      {:ok, result} = AgentServer.await_completion(pid, timeout: 10_000)
  """
  @spec await_completion(server(), keyword()) :: {:ok, map()} | {:error, term()}
  def await_completion(server, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    with {:ok, pid} <- resolve_server(server) do
      try do
        GenServer.call(pid, {:await_completion, opts}, timeout)
      catch
        :exit, {:timeout, _} ->
          case status(server) do
            {:ok, s} -> {:error, {:timeout, build_timeout_diagnostic(s, timeout)}}
            _ -> {:error, :timeout}
          end
      end
    end
  end

  defp build_timeout_diagnostic(status, timeout_ms) do
    %{
      waited_ms: timeout_ms,
      server_status: status.snapshot.status,
      queue_length: Status.queue_length(status),
      iteration: Status.iteration(status),
      hint: infer_timeout_hint(status)
    }
  end

  defp infer_timeout_hint(status) do
    case status.snapshot.status do
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
    with {:ok, pid} <- resolve_server(server),
         {:ok, %State{agent: agent, agent_module: agent_module} = state} <-
           GenServer.call(pid, :get_state) do
      snapshot = agent_module.strategy_snapshot(agent)

      {:ok,
       %Status{
         agent_module: agent_module,
         agent_id: state.id,
         pid: pid,
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

  - `:interval_ms` - Polling interval in milliseconds (default: 100)

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
    interval_ms = Keyword.get(opts, :interval_ms, 100)

    Stream.repeatedly(fn ->
      case status(server) do
        {:ok, status} ->
          Process.sleep(interval_ms)
          status

        {:error, reason} ->
          raise "Failed to get status: #{inspect(reason)}"
      end
    end)
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
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, {:set_debug, enabled})
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
    with {:ok, pid} <- resolve_server(server) do
      GenServer.call(pid, {:recent_events, opts})
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
    case Registry.lookup(registry, id) do
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
    case resolve_server(server) do
      {:ok, pid} -> Process.alive?(pid)
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
    with {:ok, pid} <- resolve_server(server) do
      try do
        GenServer.call(pid, {:attach, owner_pid})
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
    with {:ok, pid} <- resolve_server(server) do
      try do
        GenServer.call(pid, {:detach, owner_pid})
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
    with {:ok, pid} <- resolve_server(server) do
      GenServer.cast(pid, :touch)
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(raw_opts) do
    opts = if is_map(raw_opts), do: Map.to_list(raw_opts), else: raw_opts

    with {:ok, options} <- Options.new(opts),
         {:ok, agent_module, agent} <- resolve_agent(options),
         {:ok, state} <- State.from_options(options, agent_module, agent) do
      # Register in Registry
      Registry.register(state.registry, state.id, %{})

      # Monitor parent if present
      state = maybe_monitor_parent(state)

      {:ok, state, {:continue, :post_init}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:post_init, state) do
    agent_module = state.agent_module

    state =
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

    signal_router = SignalRouter.build(state)
    state = %{state | signal_router: signal_router}

    # Start plugin children
    state = start_plugin_children(state)

    # Start plugin subscription sensors
    state = start_plugin_subscriptions(state)

    # Register plugin schedules (cron jobs)
    state = register_plugin_schedules(state)

    notify_parent_of_startup(state)

    state = start_drain_if_idle(state)

    # Initialize lifecycle module (starts idle timer if needed)
    lifecycle_opts = [
      idle_timeout: state.lifecycle.idle_timeout,
      pool: state.lifecycle.pool,
      pool_key: state.lifecycle.pool_key,
      persistence: state.lifecycle.persistence
    ]

    state = state.lifecycle.mod.init(lifecycle_opts, state)

    {:noreply, State.set_status(state, :idle)}
  end

  defp init_signal do
    Signal.new!("jido.strategy.init", %{}, source: "/agent/system")
  end

  @impl true
  def handle_call({:signal, %Signal{} = signal}, _from, state) do
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      case process_signal(traced_signal, state) do
        {:ok, new_state, resolved_action} ->
          transformed_agent =
            run_plugin_transform_hooks(new_state.agent, resolved_action, traced_signal, new_state)

          {:reply, {:ok, transformed_agent}, new_state}

        {:error, reason, new_state} ->
          {:reply, {:error, reason}, new_state}
      end
    after
      TraceContext.clear()
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

    case completion_from_agent_state(state.agent.state, status_path, result_path, error_path) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      :pending ->
        {caller_pid, _tag} = from
        monitor_ref = Process.monitor(caller_pid)

        waiter = %{
          from: from,
          monitor_ref: monitor_ref,
          status_path: status_path,
          result_path: result_path,
          error_path: error_path
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
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      case process_signal(traced_signal, state) do
        {:ok, new_state, _resolved_action} -> {:noreply, new_state}
        {:error, _reason, new_state} -> {:noreply, new_state}
      end
    after
      TraceContext.clear()
    end
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:drain, state) do
    case State.dequeue(state) do
      {:empty, s} ->
        s = %{s | processing: false}
        s = State.set_status(s, :idle)
        {:noreply, s}

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

  def handle_info({:scheduled_signal, %Signal{} = signal}, state) do
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      case process_signal(traced_signal, state) do
        {:ok, new_state, _resolved_action} -> {:noreply, new_state}
        {:error, _reason, new_state} -> {:noreply, new_state}
      end
    after
      TraceContext.clear()
    end
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
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
        {_popped_waiter, new_waiters} = Map.pop(state.completion_waiters, ref)
        state = %{state | completion_waiters: new_waiters}

        if match?(%{parent: %ParentRef{pid: ^pid}}, state) do
          handle_parent_down(state, pid, reason)
        else
          handle_child_down(state, pid, reason)
        end
    end
  end

  def handle_info({:timeout, ref, :lifecycle_idle_timeout}, state) do
    if state.lifecycle.idle_timer == ref do
      # Clear the timer so stale messages don't trigger after cancel/reset.
      state = %{state | lifecycle: %{state.lifecycle | idle_timer: nil}}

      case state.lifecycle.mod.handle_event(:idle_timeout, state) do
        {:cont, state} -> {:noreply, state}
        {:stop, reason, state} -> {:stop, reason, state}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:signal, %Signal{} = signal}, state) do
    {traced_signal, _ctx} = TraceContext.ensure_from_signal(signal)

    try do
      case process_signal(traced_signal, state) do
        {:ok, new_state, _resolved_action} -> {:noreply, new_state}
        {:error, _reason, new_state} -> {:noreply, new_state}
      end
    after
      TraceContext.clear()
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # Delegate to lifecycle module for persistence/hibernation
    state.lifecycle.mod.terminate(reason, state)

    # Clean up all cron jobs owned by this agent
    Enum.each(state.cron_jobs, fn {_job_id, pid} ->
      if is_pid(pid) and Process.alive?(pid) do
        Jido.Scheduler.cancel(pid)
      end
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Internal: Signal Processing
  # ---------------------------------------------------------------------------

  defp process_signal(%Signal{} = signal, %State{signal_router: router} = state) do
    start_time = System.monotonic_time()
    metadata = build_signal_metadata(state, signal)

    # Record debug event for signal received
    state =
      State.record_debug_event(state, :signal_received, %{
        type: signal.type,
        id: signal.id
      })

    emit_telemetry(
      [:jido, :agent_server, :signal, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      do_process_signal(signal, router, state, start_time, metadata)
    catch
      kind, reason ->
        emit_telemetry(
          [:jido, :agent_server, :signal, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
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
    emit_telemetry(
      [:jido, :agent_server, :signal, :stop],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{error: reason})
    )

    error =
      Jido.Error.routing_error("No route for signal", %{
        signal_type: signal.type,
        reason: reason
      })

    error_directive = %Directive.Error{error: error, context: :routing}
    enqueue_error_directive(reason, signal, [error_directive], state)
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
    end)
    |> normalize_hook_result()
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

    try do
      case spec.module.handle_signal(signal, context) do
        {:ok, {:override, action_spec}} ->
          {:halt, {:override, action_spec}}

        {:ok, {:continue, %Signal{} = new_signal}} ->
          {:cont, {:continue, new_signal}}

        {:ok, {:override, action_spec, %Signal{} = new_signal}} ->
          {:halt, {:override, action_spec, new_signal}}

        {:ok, _} ->
          {:cont, :continue}

        {:error, reason} ->
          error =
            Jido.Error.execution_error(
              "Plugin handle_signal failed",
              %{plugin: spec.module, reason: reason}
            )

          {:halt, {:error, error}}
      end
    rescue
      e ->
        Logger.error(
          "Plugin #{inspect(spec.module)} handle_signal crashed: #{Exception.message(e)}"
        )

        error =
          Jido.Error.execution_error(
            "Plugin handle_signal crashed",
            %{plugin: spec.module, exception: Exception.message(e)}
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

      try do
        spec.module.transform_result(action_term, agent_acc, context)
      rescue
        e ->
          Logger.error(
            "Plugin #{inspect(spec.module)} transform_result crashed: #{Exception.message(e)}"
          )

          agent_acc
      end
    end)
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
      start_plugin_spec_children(acc_state, spec.module, config)
    end)
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

  defp start_plugin_child(%State{} = state, plugin_module, %{start: {m, f, a}} = spec) do
    case apply(m, f, a) do
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
      context = %{
        agent_ref: via_tuple(acc_state.id, acc_state.registry),
        agent_id: acc_state.id,
        agent_module: agent_module,
        plugin_spec: spec,
        jido_instance: acc_state.jido
      }

      config = spec.config || %{}

      subscriptions =
        if function_exported?(spec.module, :subscriptions, 2),
          do: spec.module.subscriptions(config, context),
          else: []

      Enum.reduce(subscriptions, acc_state, fn {sensor_module, sensor_config}, inner_state ->
        start_subscription_sensor(inner_state, spec.module, sensor_module, sensor_config, context)
      end)
    end)
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

    case SensorRuntime.start_link(opts) do
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
      register_schedule(acc_state, schedule_spec)
    end)
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

    signal = Signal.new!(signal_type, %{}, source: "/agent/#{agent_id}/schedule")

    opts = if timezone, do: [timezone: timezone], else: []

    result =
      Jido.Scheduler.run_every(
        fn ->
          _ = Jido.AgentServer.cast(agent_id, signal)
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

        new_cron_jobs = Map.put(state.cron_jobs, job_id, pid)
        %{state | cron_jobs: new_cron_jobs}

      {:error, reason} ->
        Logger.error(
          "AgentServer #{agent_id} failed to register schedule #{inspect(job_id)}: #{inspect(reason)}"
        )

        state
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Drain Loop
  # ---------------------------------------------------------------------------

  defp start_drain_if_idle(%State{processing: false} = state) do
    send(self(), :drain)
    %{state | processing: true, status: :processing}
  end

  defp start_drain_if_idle(%State{} = state), do: state

  defp continue_draining(state) do
    if State.queue_empty?(state) do
      {:noreply, %{state | processing: false} |> State.set_status(:idle)}
    else
      send(self(), :drain)
      {:noreply, %{state | processing: true, status: :processing}}
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

      Process.demonitor(waiter.monitor_ref, [:flush])
      GenServer.reply(waiter.from, {:ok, result})
    end)

    %{state | completion_waiters: Map.new(still_waiting)}
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

  defp resolve_server(pid) when is_pid(pid), do: {:ok, pid}

  defp resolve_server({:via, _, _} = via) do
    case GenServer.whereis(via) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(name) when is_atom(name) do
    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_server(id) when is_binary(id) do
    # String IDs require explicit registry lookup via Jido.whereis/2
    {:error,
     {:invalid_server,
      "String IDs require explicit registry lookup. Use Jido.whereis(MyApp.Jido, \"#{id}\") first or pass the pid directly."}}
  end

  defp resolve_server(_), do: {:error, :invalid_server}

  # ---------------------------------------------------------------------------
  # Internal: Hierarchy
  # ---------------------------------------------------------------------------

  defp maybe_monitor_parent(%State{parent: %ParentRef{pid: pid}} = state) when is_pid(pid) do
    Process.monitor(pid)
    state
  end

  defp maybe_monitor_parent(state), do: state

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

    traced_child_started =
      case Trace.put(child_started, Trace.new_root()) do
        {:ok, s} -> s
        {:error, _} -> child_started
      end

    _ = cast(parent.pid, traced_child_started)
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

    traced_signal =
      case Trace.put(signal, Trace.new_root()) do
        {:ok, s} -> s
        {:error, _} -> signal
      end

    case process_signal(traced_signal, state) do
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

      traced_signal =
        case Trace.put(signal, Trace.new_root()) do
          {:ok, s} -> s
          {:error, _} -> signal
        end

      case process_signal(traced_signal, state) do
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

  # ---------------------------------------------------------------------------
  # Internal: Telemetry
  # ---------------------------------------------------------------------------

  defp exec_directive_with_telemetry(directive, signal, state) do
    start_time = System.monotonic_time()

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

    emit_telemetry(
      [:jido, :agent_server, :directive, :start],
      %{system_time: System.system_time()},
      metadata
    )

    try do
      result = DirectiveExec.exec(directive, signal, state)

      emit_telemetry(
        [:jido, :agent_server, :directive, :stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, %{result: result_type(result)})
      )

      result
    catch
      kind, reason ->
        emit_telemetry(
          [:jido, :agent_server, :directive, :exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, error: reason})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:async, _, _}), do: :async
  defp result_type({:stop, _, _}), do: :stop

  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
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
end
