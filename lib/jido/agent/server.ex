defmodule Jido.Agent.Server do
  @moduledoc """
  Agent Server implementation using GenStateMachine for robust state management.

  This module provides the core server functionality for Jido agents, handling:
  - Agent lifecycle management with explicit state transitions  
  - Signal processing and routing
  - Instruction execution
  - Queue management with backpressure
  - Automatic state validation and debugging

  ## Agent States

  - `:initializing` - Server is starting up and mounting callbacks
  - `:idle` - Server is ready to accept and process signals
  - `:planning` - Server is preparing action execution plans
  - `:running` - Server is actively executing instructions
  - `:paused` - Server execution is temporarily suspended

  ## State Transitions

  ```
  initializing -> idle        (after successful initialization)
  idle         -> planning    (when planning mode is activated)
  idle         -> running     (when executing instructions directly)  
  planning     -> running     (when plan execution begins)
  planning     -> idle        (when planning is cancelled)
  running      -> paused      (when execution is paused)
  running      -> idle        (when execution completes)
  paused       -> running     (when execution resumes)
  paused       -> idle        (when execution is cancelled)
  ```

  ## Operation Modes

  - `:auto` - Signals are processed automatically as they arrive
  - `:step` - Signals require manual processing (useful for debugging)

  ## Usage

  ```elixir
  # Start an agent server
  {:ok, pid} = Jido.Agent.Server.start_link(agent: MyAgent)

  # Send synchronous instruction
  instruction = Jido.Instruction.new!(%{action: MyAction, params: %{key: "value"}})
  {:ok, result} = Jido.Agent.Server.call(pid, instruction)

  # Send asynchronous signal  
  {:ok, signal_id} = Jido.Agent.Server.cast(pid, instruction)

  # Get current state
  {:ok, state} = Jido.Agent.Server.state(pid)
  ```
  """

  use GenStateMachine, callback_mode: :handle_event_function

  alias Jido.Agent.Server.Callback, as: ServerCallback
  alias Jido.Agent.Server.Options, as: ServerOptions
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Agent.Server.Process, as: ServerProcess
  alias Jido.Agent.Server.Router, as: ServerRouter
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.SignalProcessor
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

  # Reply reference cleanup timeout (30 seconds)
  @reply_cleanup_timeout 30_000

  # Queue processing batch size for backpressure
  @queue_batch_size 10

  # Queue processing yield timeout (milliseconds)
  @queue_yield_timeout 100

  ## Public API

  @doc """
  Starts a new agent server process.
  """
  @spec start_link([start_option()]) :: GenStateMachine.on_start()
  def start_link(opts) do
    # Ensure ID consistency
    opts = ensure_id_consistency(opts)

    with {:ok, agent} <- build_agent(opts),
         # Update the opts with the agent's ID to ensure consistency
         opts = Keyword.put(opts, :agent, agent) |> Keyword.put(:id, agent.id),
         {:ok, opts} <- ServerOptions.validate_server_opts(opts) do
      agent_id = agent.id
      registry = Keyword.get(opts, :registry, Jido.Registry)

      GenStateMachine.start_link(
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
      GenStateMachine.call(pid, {:signal, signal})
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
      case GenStateMachine.call(pid, {:signal, signal}, timeout) do
        {:ok, response} ->
          {:ok, response}

        other ->
          other
      end
    end
  end

  def call(agent, %Instruction{} = instruction, timeout) do
    with {:ok, validated_instruction} <- validate_instruction(instruction),
         {:ok, signal} <- Signal.new(%{type: "instruction", data: validated_instruction}) do
      call(agent, signal, timeout)
    else
      {:error, reason} ->
        {:error, {:invalid_input, reason}}
    end
  end

  @doc """
  Sends an asynchronous signal to an agent.
  """
  @spec cast(pid() | atom() | {atom(), node()}, Signal.t() | Instruction.t()) ::
          {:ok, String.t()} | {:error, term()}
  def cast(agent, %Signal{} = signal) do
    with {:ok, pid} <- Jido.resolve_pid(agent) do
      GenStateMachine.cast(pid, {:signal, signal})
      {:ok, signal.id}
    end
  end

  def cast(agent, %Instruction{} = instruction) do
    with {:ok, validated_instruction} <- validate_instruction(instruction),
         {:ok, signal} <- Signal.new(%{type: "instruction", data: validated_instruction}) do
      cast(agent, signal)
    else
      {:error, reason} ->
        {:error, {:invalid_input, reason}}
    end
  end

  @doc """
  Returns a via tuple for process registration.
  """
  @spec via_tuple(String.t(), module()) :: {:via, Registry, {module(), String.t()}}
  def via_tuple(name, registry) do
    {:via, Registry, {registry, name}}
  end

  ## GenStateMachine callbacks

  @impl GenStateMachine
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
         {:ok, state} <- ServerCallback.mount(state) do
      agent_name = state.agent.__struct__ |> Module.split() |> List.last()

      ServerOutput.log(
        state,
        :info,
        "Initializing #{agent_name} Agent Server, ID: #{state.agent.id}, Log Level: #{state.log_level}"
      )

      # Start in initializing state, will transition to idle
      {:ok, :initializing, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_event(:enter, :initializing, state) do
    :started
    |> ServerSignal.event_signal(state, %{agent_id: state.agent.id})
    |> ServerOutput.emit(state)

    # Use proper state transition validation
    case ServerState.transition(state, :idle) do
      {:ok, new_state} ->
        {:next_state, :idle, new_state}

      {:error, reason} ->
        {:stop, {:invalid_transition, reason}, state}
    end
  end

  def handle_event(:enter, new_state, state) do
    # Emit transition event
    :transition_succeeded
    |> ServerSignal.event_signal(state, %{from: state.status, to: new_state})
    |> ServerOutput.emit(state)

    # Update the state status to match the GenStateMachine state
    updated_state = %{state | status: new_state}

    # Trigger queue processing when entering certain states
    actions =
      case new_state do
        current_state when current_state in [:idle, :running] ->
          case :queue.len(updated_state.pending_signals) do
            0 -> []
            _ -> [{:next_event, :internal, :process_queue}]
          end

        _ ->
          []
      end

    {:keep_state, updated_state, actions}
  end

  # Handle state queries
  @impl GenStateMachine
  def handle_event({:call, from}, {:signal, %Signal{type: @cmd_state}}, _state, data) do
    {:keep_state_and_data, [{:reply, from, {:ok, data}}]}
  end

  # Handle queue size queries
  def handle_event({:call, from}, {:signal, %Signal{type: @cmd_queue_size}}, _state, data) do
    case ServerState.check_queue_size(data) do
      {:ok, queue_size} ->
        response = %{queue_size: queue_size, max_size: data.max_queue_size}
        {:keep_state_and_data, [{:reply, from, {:ok, response}}]}

      {:error, :queue_overflow} ->
        queue_size = :queue.len(data.pending_signals)

        error_data = %{
          reason: :queue_overflow,
          current_size: queue_size,
          max_size: data.max_queue_size
        }

        {:keep_state_and_data, [{:reply, from, {:error, error_data}}]}
    end
  end

  # Handle synchronous signals
  def handle_event({:call, from}, {:signal, %Signal{} = signal}, _current_state, data) do
    # Store the from reference for reply later
    data = ServerState.store_reply_ref(data, signal.id, from)

    # Enqueue the signal
    case ServerState.enqueue(data, signal) do
      {:ok, new_data} ->
        # Trigger queue processing and set cleanup timeout for reply ref
        actions = [
          {:next_event, :internal, :process_queue},
          {:timeout, @reply_cleanup_timeout, {:cleanup_reply_ref, signal.id}}
        ]

        {:keep_state, new_data, actions}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  # Handle asynchronous signals
  def handle_event(:cast, {:signal, %Signal{} = signal}, _state, data) do
    # Enqueue the signal
    case ServerState.enqueue(data, signal) do
      {:ok, new_data} ->
        # Trigger queue processing
        {:keep_state, new_data, [{:next_event, :internal, :process_queue}]}

      {:error, _reason} ->
        :keep_state_and_data
    end
  end

  # Handle queue processing
  def handle_event(:internal, :process_queue, state, data) do
    case should_process_queue?(state, data) do
      true ->
        # Process signals in batches for better performance and backpressure
        case SignalProcessor.process_signal_batch(data, @queue_batch_size) do
          {:ok, new_data, replies, :more_signals} ->
            # Send replies and continue processing after a yield
            reply_actions = Enum.map(replies, fn {from, response} -> {:reply, from, response} end)
            continue_actions = [{:timeout, @queue_yield_timeout, :continue_queue_processing}]
            {:keep_state, new_data, reply_actions ++ continue_actions}

          {:ok, new_data, replies, :queue_empty} ->
            # Send replies and stop processing
            reply_actions = Enum.map(replies, fn {from, response} -> {:reply, from, response} end)
            {:keep_state, new_data, reply_actions}

          {:error, :empty_queue} ->
            :keep_state_and_data
        end

      false ->
        :keep_state_and_data
    end
  end

  def handle_event(:timeout, :continue_queue_processing, state, data) do
    handle_event(:internal, :process_queue, state, data)
  end

  # Handle process termination
  def handle_event(:info, {:EXIT, _exit_pid, reason}, _state, data) do
    {:stop, reason, data}
  end

  def handle_event(:info, {:DOWN, _monitor_ref, :process, pid, reason}, _state, data) do
    :process_terminated
    |> ServerSignal.event_signal(data, %{pid: pid, reason: reason})
    |> ServerOutput.emit(data)

    :keep_state_and_data
  end

  # Handle timeouts
  def handle_event(:timeout, :queue_processing, state, data) do
    handle_event(:internal, :process_queue, state, data)
  end

  def handle_event(:timeout, {:cleanup_reply_ref, signal_id}, _state, data) do
    case ServerState.get_reply_ref(data, signal_id) do
      nil ->
        :keep_state_and_data

      from ->
        updated_data = ServerState.remove_reply_ref(data, signal_id)
        {:keep_state, updated_data, [{:reply, from, {:error, :timeout}}]}
    end
  end

  # Handle unrecognized events
  def handle_event(_event_type, _event_content, _current_state, _data) do
    :keep_state_and_data
  end

  @impl GenStateMachine
  def terminate(reason, _state, data) do
    require Logger
    stacktrace = Process.info(self(), :current_stacktrace)

    # Format the error message in a more readable way
    error_msg = """
    #{data.agent.__struct__} server terminating

    Reason:
    #{Exception.format_banner(:error, reason)}

    Stacktrace:
    #{Exception.format_stacktrace(elem(stacktrace, 1))}

    Agent State:
    - ID: #{data.agent.id}
    - Status: #{data.status}
    - Queue Size: #{:queue.len(data.pending_signals)}
    - Mode: #{data.mode}
    """

    Logger.error(error_msg)

    case ServerCallback.shutdown(data, reason) do
      {:ok, new_data} ->
        :stopped
        |> ServerSignal.event_signal(data, %{reason: reason})
        |> ServerOutput.emit(data)

        ServerProcess.stop_supervisor(new_data)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenStateMachine
  def code_change(old_vsn, state, data, extra) do
    case ServerCallback.code_change(data, old_vsn, extra) do
      {:ok, new_data} -> {:ok, state, new_data}
      error -> error
    end
  end

  @impl GenStateMachine
  def format_status(_opts, [_pdict, state, data]) do
    %{
      state: state,
      data: data,
      status: data.status,
      agent_id: data.agent.id,
      queue_size: :queue.len(data.pending_signals),
      child_processes: DynamicSupervisor.which_children(data.child_supervisor)
    }
  end

  ## Private functions

  @doc false
  defp validate_instruction(%Instruction{action: action} = instruction) when not is_nil(action) do
    cond do
      is_atom(action) and Code.ensure_loaded?(action) ->
        {:ok, instruction}

      is_function(action) ->
        {:ok, instruction}

      true ->
        {:error, {:invalid_action, action}}
    end
  end

  defp validate_instruction(%Instruction{action: nil}) do
    {:error, :missing_action}
  end

  defp validate_instruction(invalid) do
    {:error, {:invalid_instruction, invalid}}
  end

  defp should_process_queue?(state, data) do
    case {state, data.mode} do
      # Allow processing during initialization
      {:initializing, :auto} -> true
      {:idle, :auto} -> true
      {:running, :auto} -> true
      # In step mode, manual processing required
      {:idle, :step} -> false
      {:running, :step} -> false
      _ -> false
    end
  end

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

                  try do
                    case apply(agent_input, :new, [id, initial_state]) do
                      %_{} = agent ->
                        {:ok, agent}

                      other ->
                        {:error, {:invalid_agent_return, other}}
                    end
                  rescue
                    error ->
                      {:error, {:agent_creation_failed, error}}
                  catch
                    kind, reason ->
                      {:error, {:agent_creation_exception, {kind, reason}}}
                  end
                else
                  {:error, :invalid_agent}
                end

              {:error, reason} ->
                {:error, {:module_load_failed, reason}}
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
