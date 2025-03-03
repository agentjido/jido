defmodule Jido.Agent.Server do
  @moduledoc """
  GenServer implementation for managing agent processes.

  This server handles the lifecycle and runtime execution of agents, including:
  - Agent initialization and startup
  - Signal processing and routing
  - State management and transitions
  - Child process supervision
  - Graceful shutdown

  The server can be started in different modes (`:auto` or `:manual`) and supports
  both synchronous (call) and asynchronous (cast) signal handling.
  """

  use ExDbug, enabled: false
  use GenServer

  alias Jido.Agent.Server.Callback, as: ServerCallback
  alias Jido.Agent.Server.Options, as: ServerOptions
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.Agent.Server.Runtime, as: ServerRuntime
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Skills, as: ServerSkills
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal

  @type start_option ::
          {:id, String.t()}
          | {:agent, module() | struct()}
          | {:initial_state, map()}
          | {:registry, module()}
          | {:mode, :auto | :manual}
          | {:dispatch, pid() | {module(), term()}}
          | {:log_level, Logger.level()}
          | {:max_queue_size, non_neg_integer()}

  @cmd_state ServerSignal.join_type(ServerSignal.type({:cmd, :state}))
  @cmd_queue_size ServerSignal.join_type(ServerSignal.type({:cmd, :queue_size}))
  @doc """
  Starts a new agent server process.

  ## Options
    * `:id` - Unique identifier for the agent (auto-generated if not provided)
    * `:agent` - Agent module or struct to be managed
    * `:initial_state` - Initial state map for the agent
    * `:registry` - Registry for process registration
    * `:mode` - Operation mode (`:auto` or `:manual`)
    * `:output` - Output destination for agent signals
    * `:log_level` - Logging level
    * `:max_queue_size` - Maximum size of pending signals queue

  ## Returns
    * `{:ok, pid}` - Successfully started server process
    * `{:error, reason}` - Failed to start server
  """
  @spec start_link([start_option()]) :: GenServer.on_start()
  def start_link(opts) do
    dbug("Starting agent server", opts: opts)
    opts = Keyword.put_new(opts, :id, Jido.Util.generate_id())

    with {:ok, agent} <- build_agent(opts),
         opts = Keyword.put(opts, :agent, agent),
         {:ok, opts} <- ServerOptions.validate_server_opts(opts) do
      agent_id = Keyword.get(opts, :agent).id
      registry = Keyword.get(opts, :registry)

      GenServer.start_link(
        __MODULE__,
        opts,
        name: via_tuple(agent_id, registry)
      )
    end
  end

  @doc """
  Returns a child specification for starting the server under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    dbug("Building child spec", opts: opts)
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: :infinity,
      restart: :permanent,
      type: :supervisor
    }
  end

  @doc """
  Gets the current state of an agent.
  """
  @spec state(pid() | atom() | {atom(), node()}) :: {:ok, ServerState.t()} | {:error, term()}
  def state(agent) do
    dbug("Getting state for agent", agent: agent)

    with {:ok, pid} <- Jido.resolve_pid(agent),
         signal <- ServerSignal.cmd_signal(:state, nil) do
      GenServer.call(pid, {:signal, signal})
    end
  end

  @doc """
  Sends a synchronous signal to an agent and waits for the response.
  """
  @spec call(pid() | atom() | {atom(), node()}, Signal.t()) ::
          {:ok, Signal.t()} | {:error, term()}
  def call(agent, %Signal{} = signal, timeout \\ 5000) do
    dbug("Calling agent", agent: agent, signal: signal)

    with {:ok, pid} <- Jido.resolve_pid(agent) do
      case GenServer.call(pid, {:signal, signal}, timeout) do
        {:ok, response} ->
          dbug("Call successful", response: response)
          {:ok, response}

        other ->
          dbug("Call failed", result: other)
          other
      end
    end
  end

  @doc """
  Sends an asynchronous signal to an agent.
  """
  @spec cast(pid() | atom() | {atom(), node()}, Signal.t()) ::
          {:ok, String.t()} | {:error, term()}
  def cast(agent, %Signal{} = signal) do
    dbug("Casting signal to agent", agent: agent, signal: signal)

    with {:ok, pid} <- Jido.resolve_pid(agent) do
      GenServer.cast(pid, {:signal, signal})
      {:ok, signal.id}
    end
  end

  @impl true
  def init(opts) do
    dbug("Initializing agent server", opts: opts)
    opts = Keyword.put_new(opts, :id, Jido.Util.generate_id())

    with {:ok, agent} <- build_agent(opts),
         opts = Keyword.put(opts, :agent, agent),
         {:ok, opts} <- ServerOptions.validate_server_opts(opts),
         {:ok, state} <- build_initial_state_from_opts(opts),
         {:ok, state} <- ServerProcess.start_supervisor(state),
         {:ok, state, opts} <- ServerSkills.build(state, opts),
         {:ok, state} <- ServerRouter.build(state, opts),
         {:ok, state, _pids} <- ServerProcess.start(state, opts[:child_specs]),
         {:ok, state} <- ServerCallback.mount(state),
         {:ok, state} <- ServerState.transition(state, :idle) do
      dbug("Agent server initialized successfully")

      :started
      |> ServerSignal.event_signal(state, %{agent_id: state.agent.id})
      |> ServerOutput.emit()

      {:ok, state}
    else
      {:error, reason} ->
        dbug("Failed to initialize agent server", reason: reason)
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:signal, %Signal{type: @cmd_state}}, _from, %ServerState{} = state) do
    dbug("Handling state command")
    {:reply, {:ok, state}, state}
  end

  def handle_call(
        {:signal, %Signal{type: @cmd_queue_size}},
        _from,
        %ServerState{} = state
      ) do
    dbug("Handling queue size command")

    case ServerState.check_queue_size(state) do
      {:ok, _queue_size} ->
        {:reply, {:ok, state}, state}

      {:error, :queue_overflow} ->
        {:reply, {:error, :queue_overflow}, state}
    end
  end

  def handle_call({:signal, %Signal{} = signal}, from, %ServerState{} = state) do
    dbug("Handling signal", type: signal.type, signal: signal)

    # Store the from reference for reply later
    state = ServerState.store_reply_ref(state, signal.id, from)
    dbug("Stored reply ref", ref: signal.id, signal: signal, from: from)

    # Enqueue the signal
    case ServerState.enqueue(state, signal) do
      {:ok, new_state} ->
        # Trigger queue processing
        Process.send_after(self(), :process_queue, 0)
        {:noreply, new_state}

      {:error, reason} ->
        dbug("Failed to enqueue signal", reason: reason)
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(_unhandled, _from, state) do
    dbug("Unhandled call", call: _unhandled)
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast({:signal, %Signal{} = signal}, %ServerState{} = state) do
    dbug("Handling cast signal", signal: signal)

    # Enqueue the signal
    case ServerState.enqueue(state, signal) do
      {:ok, new_state} ->
        # Trigger queue processing
        Process.send_after(self(), :process_queue, 0)
        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  def handle_cast(_unhandled, state) do
    dbug("Unhandled cast", cast: _unhandled)
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:signal, %Signal{type: @cmd_queue_size} = _signal},
        %ServerState{} = state
      ) do
    dbug("Handling info queue size signal", signal: _signal)

    case ServerState.check_queue_size(state) do
      {:ok, _queue_size} ->
        {:noreply, state}

      {:error, :queue_overflow} ->
        dbug("Queue overflow detected")
        {:noreply, state}
    end
  end

  def handle_info({:signal, %Signal{} = signal}, %ServerState{} = state) do
    dbug("Handling info signal", signal: signal)

    # Enqueue the signal
    case ServerState.enqueue(state, signal) do
      {:ok, new_state} ->
        # Trigger queue processing
        Process.send_after(self(), :process_queue, 0)
        {:noreply, new_state}

      {:error, _reason} ->
        dbug("Failed to enqueue info signal", reason: _reason)
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, _pid, reason}, %ServerState{} = state) do
    dbug("Process exited", pid: _pid, reason: reason)
    {:stop, reason, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %ServerState{} = state) do
    dbug("DOWN message received", ref: _ref, pid: pid, reason: reason)

    :process_terminated
    |> ServerSignal.event_signal(state, %{pid: pid, reason: reason})
    |> ServerOutput.emit()

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    dbug("Timeout received")
    {:noreply, state}
  end

  def handle_info(:process_queue, state) do
    case ServerRuntime.process_signals_in_queue(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_info(_unhandled, state) do
    dbug("Unhandled info", info: _unhandled)
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %ServerState{} = state) do
    dbug("Terminating agent server", reason: reason)
    require Logger
    stacktrace = Process.info(self(), :current_stacktrace)

    # Format the error message in a more readable way
    error_msg = """
    #{state.agent.__struct__} server terminating

    Reason:
    #{Exception.format_banner(:error, reason)}

    Stacktrace:
    #{Exception.format_stacktrace(elem(stacktrace, 1))}

    Agent State:
    - ID: #{state.agent.id}
    - Status: #{state.status}
    - Queue Size: #{:queue.len(state.pending_signals)}
    - Mode: #{state.mode}
    """

    Logger.error(error_msg)

    case ServerCallback.shutdown(state, reason) do
      {:ok, new_state} ->
        :stopped
        |> ServerSignal.event_signal(state, %{reason: reason})
        |> ServerOutput.emit()

        ServerProcess.stop_supervisor(new_state)
        :ok

      {:error, reason} ->
        dbug("Failed to shutdown server", reason: reason)
        {:error, reason}
    end
  end

  @impl true
  def code_change(old_vsn, %ServerState{} = state, extra) do
    dbug("Code change", old_vsn: old_vsn, extra: extra)
    ServerCallback.code_change(state, old_vsn, extra)
  end

  @impl true
  def format_status(_opts, [_pdict, state]) do
    dbug("Formatting status")

    %{
      state: state,
      status: state.status,
      agent_id: state.agent.id,
      queue_size: :queue.len(state.pending_signals),
      child_processes: DynamicSupervisor.which_children(state.child_supervisor)
    }
  end

  @doc """
  Returns a via tuple for process registration.
  """
  @spec via_tuple(String.t(), module()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(name, registry) do
    dbug("Creating via tuple", name: name, registry: registry)
    {:via, Registry, {registry, name}}
  end

  @spec build_agent(keyword()) :: {:ok, struct()} | {:error, :invalid_agent}
  defp build_agent(opts) do
    dbug("Building agent", opts: opts)

    case Keyword.fetch(opts, :agent) do
      {:ok, agent_input} when not is_nil(agent_input) ->
        cond do
          is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 2) ->
            id = Keyword.get(opts, :id)
            initial_state = Keyword.get(opts, :initial_state, %{})
            {:ok, agent_input.new(id, initial_state)}

          is_struct(agent_input) ->
            # Check if the provided ID differs from the agent's ID
            provided_id = Keyword.get(opts, :id)

            if provided_id && provided_id != agent_input.id do
              require Logger

              Logger.warning(
                "Agent ID mismatch: provided ID '#{provided_id}' will be superseded by agent's ID '#{agent_input.id}'"
              )
            end

            {:ok, agent_input}

          true ->
            dbug("Invalid agent input")
            {:error, :invalid_agent}
        end

      _ ->
        dbug("Missing agent input")
        {:error, :invalid_agent}
    end
  end

  @spec build_initial_state_from_opts(keyword()) :: {:ok, ServerState.t()}
  defp build_initial_state_from_opts(opts) do
    dbug("Building initial state from options", opts: opts)

    state = %ServerState{
      agent: opts[:agent],
      mode: opts[:mode],
      log_level: opts[:log_level],
      max_queue_size: opts[:max_queue_size],
      registry: opts[:registry],
      dispatch: opts[:dispatch],
      skills: []
    }

    {:ok, state}
  end
end
