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
  alias Jido.Instruction
  # Default actions to register with every agent
  @default_actions [
    Jido.Tools.Basic.Log,
    Jido.Tools.Basic.Sleep,
    Jido.Tools.Basic.Noop,
    Jido.Tools.Basic.Inspect,
    Jido.Tools.Basic.Today
  ]

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
    * `:routes` - Routes for the agent
    * `:output` - Output destination for agent signals
    * `:log_level` - Logging level
    * `:max_queue_size` - Maximum size of pending signals queue

  ## Returns
    * `{:ok, pid}` - Successfully started server process
    * `{:error, reason}` - Failed to start server
  """
  @spec start_link([start_option()]) :: GenServer.on_start()
  def start_link(opts) do
    # Ensure ID consistency
    opts = ensure_id_consistency(opts)

    with {:ok, agent} <- build_agent(opts),
         # Update the opts with the agent's ID to ensure consistency
         opts = Keyword.put(opts, :agent, agent) |> Keyword.put(:id, agent.id),
         {:ok, opts} <- ServerOptions.validate_server_opts(opts) do
      agent_id = agent.id
      registry = Keyword.get(opts, :registry, Jido.Registry)

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
    with {:ok, pid} <- Jido.resolve_pid(agent),
         signal <- ServerSignal.cmd_signal(:state, nil) do
      GenServer.call(pid, {:signal, signal})
    end
  end

  @doc """
  Sends a synchronous signal to an agent and waits for the response.
  """
  @spec call(pid() | atom() | {atom(), node()}, Signal.t() | Instruction.t(), timeout()) ::
          {:ok, Signal.t()} | {:error, term()}
  def call(agent, signal_or_instruction, timeout \\ 5000)

  def call(agent, %Signal{} = signal, timeout) do
    with {:ok, pid} <- Jido.resolve_pid(agent) do
      case GenServer.call(pid, {:signal, signal}, timeout) do
        {:ok, response} ->
          {:ok, response}

        other ->
          other
      end
    end
  end

  def call(agent, %Instruction{} = instruction, timeout) do
    signal = Signal.new!(%{type: "instruction", data: instruction})
    call(agent, signal, timeout)
  end

  @doc """
  Sends an asynchronous signal to an agent.
  """
  @spec cast(pid() | atom() | {atom(), node()}, Signal.t() | Instruction.t()) ::
          {:ok, String.t()} | {:error, term()}
  def cast(agent, %Signal{} = signal) do
    with {:ok, pid} <- Jido.resolve_pid(agent) do
      GenServer.cast(pid, {:signal, signal})
      {:ok, signal.id}
    end
  end

  def cast(agent, %Instruction{} = instruction) do
    signal = Signal.new!(%{type: "instruction", data: instruction})
    cast(agent, signal)
  end

  @impl true
  def init(opts) do
    # Ensure ID consistency - should be a no-op if already consistent from start_link
    opts = ensure_id_consistency(opts)

    with {:ok, agent} <- build_agent(opts),
         opts = Keyword.put(opts, :agent, agent),
         {:ok, opts} <- ServerOptions.validate_server_opts(opts),
         {:ok, state} <- build_initial_state_from_opts(opts),
         {:ok, state} <- register_actions(state, opts[:actions]),
         {:ok, state, opts} <- ServerSkills.build(state, opts),
         {:ok, state} <- ServerRouter.build(state, opts),
         {:ok, state, _pids} <- ServerProcess.start(state, opts[:child_specs]),
         {:ok, state} <- ServerCallback.mount(state),
         {:ok, state} <- ServerState.transition(state, :idle) do
      agent_name = state.agent.__struct__ |> Module.split() |> List.last()

      ServerOutput.log(
        state,
        :info,
        "Initializing #{agent_name} Agent Server, ID: #{state.agent.id}, Log Level: #{state.log_level}"
      )

      :started
      |> ServerSignal.event_signal(state, %{agent_id: state.agent.id})
      |> ServerOutput.emit(state)

      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:signal, %Signal{type: @cmd_state}}, _from, %ServerState{} = state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(
        {:signal, %Signal{type: @cmd_queue_size}},
        _from,
        %ServerState{} = state
      ) do
    case ServerState.check_queue_size(state) do
      {:ok, _queue_size} ->
        {:reply, {:ok, state}, state}

      {:error, :queue_overflow} ->
        {:reply, {:error, :queue_overflow}, state}
    end
  end

  def handle_call({:signal, %Signal{} = signal}, from, %ServerState{} = state) do
    # Store the from reference for reply later
    state = ServerState.store_reply_ref(state, signal.id, from)
    # Enqueue the signal
    case ServerState.enqueue(state, signal) do
      {:ok, new_state} ->
        # Trigger queue processing
        Process.send_after(self(), :process_queue, 0)
        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(_unhandled, _from, state) do
    {:reply, {:error, :unhandled_call}, state}
  end

  @impl true
  def handle_cast({:signal, %Signal{} = signal}, %ServerState{} = state) do
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
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:signal, %Signal{type: @cmd_queue_size} = _signal},
        %ServerState{} = state
      ) do
    case ServerState.check_queue_size(state) do
      {:ok, _queue_size} ->
        {:noreply, state}

      {:error, :queue_overflow} ->
        {:noreply, state}
    end
  end

  def handle_info({:signal, %Signal{} = signal}, %ServerState{} = state) do
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

  def handle_info({:EXIT, _pid, reason}, %ServerState{} = state) do
    {:stop, reason, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %ServerState{} = state) do
    :process_terminated
    |> ServerSignal.event_signal(state, %{pid: pid, reason: reason})
    |> ServerOutput.emit(state)

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    {:noreply, state}
  end

  def handle_info(:process_queue, state) do
    case ServerRuntime.process_signals_in_queue(state) do
      {:ok, new_state} -> {:noreply, new_state}
    end
  end

  def handle_info(_unhandled, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, %ServerState{} = state) do
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
        |> ServerOutput.emit(state)

        ServerProcess.stop_supervisor(new_state)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def code_change(old_vsn, %ServerState{} = state, extra) do
    ServerCallback.code_change(state, old_vsn, extra)
  end

  @impl true
  def format_status(_opts, [_pdict, state]) do
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
    {:via, Registry, {registry, name}}
  end

  @spec build_agent(keyword()) :: {:ok, Jido.Agent.t()} | {:error, :invalid_agent}
  defp build_agent(opts) do
    case Keyword.fetch(opts, :agent) do
      {:ok, agent_input} when not is_nil(agent_input) ->
        cond do
          is_atom(agent_input) ->
            # First ensure the module is loaded
            case Code.ensure_loaded(agent_input) do
              {:module, _} ->
                if :erlang.function_exported(agent_input, :new, 2) do
                  id = Keyword.get(opts, :id)
                  initial_state = Keyword.get(opts, :initial_state, %{})
                  {:ok, agent_input.new(id, initial_state)}
                else
                  {:error, :invalid_agent}
                end

              {:error, _reason} ->
                {:error, :invalid_agent}
            end

          is_struct(agent_input) ->
            # Check if the provided ID differs from the agent's ID
            provided_id = Keyword.get(opts, :id)
            agent_id = agent_input.id

            # Check for non-empty IDs that differ
            if is_binary(provided_id) && is_binary(agent_id) &&
                 provided_id != "" && agent_id != "" &&
                 provided_id != agent_id do
              require Logger

              # Always emit this warning regardless of debug settings
              Logger.warning(
                "Agent ID mismatch: provided ID '#{provided_id}' will be superseded by agent's ID '#{agent_id}'"
              )
            end

            {:ok, agent_input}

          true ->
            {:error, :invalid_agent}
        end

      _ ->
        {:error, :invalid_agent}
    end
  end

  defp build_initial_state_from_opts(opts) do
    state = %ServerState{
      agent: opts[:agent],
      opts: opts,
      mode: opts[:mode],
      log_level: opts[:log_level],
      max_queue_size: opts[:max_queue_size],
      registry: opts[:registry],
      dispatch: opts[:dispatch],
      skills: []
    }

    {:ok, state}
  end

  @spec ensure_id_consistency(keyword()) :: keyword()
  defp ensure_id_consistency(opts) do
    # Check if we have an agent with an ID
    agent_id =
      case Keyword.get(opts, :agent) do
        %{id: id} when is_binary(id) ->
          if id != "", do: id, else: nil

        _ ->
          nil
      end

    # Check if we have an explicit ID in the options
    explicit_id = Keyword.get(opts, :id)

    explicit_id =
      cond do
        is_binary(explicit_id) && explicit_id != "" -> explicit_id
        is_atom(explicit_id) -> Atom.to_string(explicit_id)
        true -> nil
      end

    cond do
      # If we have both an agent ID and an explicit ID, and they differ,
      # we'll keep the agent ID but update the options
      agent_id && explicit_id && agent_id != explicit_id ->
        Keyword.put(opts, :id, agent_id)

      # If we have an agent ID but no explicit ID, use the agent ID
      agent_id && !explicit_id ->
        Keyword.put(opts, :id, agent_id)

      # If we have an explicit ID but no agent ID, keep the explicit ID
      !agent_id && explicit_id ->
        opts

      # If we have neither, generate a new ID
      !agent_id && !explicit_id ->
        new_id = Jido.Util.generate_id()
        Keyword.put(opts, :id, new_id)

      # Otherwise, options are already consistent
      true ->
        opts
    end
  end

  defp register_actions(%ServerState{} = state, provided_actions)
       when is_list(provided_actions) do
    # Combine default actions with provided actions
    all_actions = @default_actions ++ provided_actions

    # Register actions with the agent - this should always succeed for valid actions
    {:ok, updated_agent} = Jido.Agent.register_action(state.agent, all_actions)

    {:ok, %{state | agent: updated_agent}}
  end

  defp register_actions(state, _), do: {:ok, state}
end
