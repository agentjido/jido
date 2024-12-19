defmodule Jido.Agent.Worker do
  @moduledoc """
  A GenServer implementation for managing agent state and operations in a distributed system.

  The Worker module provides a robust framework for managing agent lifecycle, state transitions,
  and command processing. It handles both synchronous and asynchronous operations while
  maintaining fault tolerance and providing comprehensive logging and telemetry.

  ## Features

  - State machine-based lifecycle management
  - Asynchronous command processing with queuing
  - PubSub-based event broadcasting
  - Comprehensive error handling and recovery
  - Telemetry integration for monitoring
  - Distributed registration via Registry

  ## States

  Workers follow a state machine pattern with these states:
  - `:initializing` - Initial startup state
  - `:idle` - Ready to accept commands
  - `:running` - Actively processing commands
  - `:paused` - Suspended command processing (queues new commands)
  - `:planning` - Planning but not executing actions

  ## Command Types

  The worker processes two main types of commands:
  1. Act commands: Asynchronous actions that modify agent state
  2. Management commands: Synchronous operations that control worker behavior

  ## Usage

  Start a worker under a supervisor:

      children = [
        {Jido.Agent.Worker,
          agent: MyAgent.new(),
          pubsub: MyApp.PubSub,
          topic: "custom.topic",
          max_queue_size: 1000  # Optional, defaults to 10000
        }
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

  Send commands to the worker:

      # Asynchronous action
      Worker.act(worker_pid, %{command: :move, destination: :kitchen})

      # Synchronous management
      {:ok, new_state} = Worker.manage(worker_pid, :pause)

  ## Events

  The worker emits these events on its PubSub topic:
  - `jido.agent.started` - Worker initialization complete
  - `jido.agent.state_changed` - Worker state transitions
  - `jido.agent.act_completed` - Action execution completed
  - `jido.agent.queue_overflow` - Queue size exceeded max_queue_size

  ## Error Handling

  The worker implements several error handling mechanisms:
  - Command validation and queueing
  - State transition validation
  - Automatic command retries (configurable)
  - Dead letter handling for failed commands
  - Queue size limits with overflow protection
  """
  use GenServer
  use Private
  use Jido.Util, debug_enabled: true
  alias Jido.Signal
  alias Jido.Agent.Worker.State
  require Logger

  @default_max_queue_size 10_000

  @typedoc """
  Management commands that can be sent to the worker.

  - `:replan` - Trigger replanning of current actions
  - `:pause` - Suspend command processing
  - `:resume` - Resume command processing
  - `:reset` - Reset to initial state
  - `:stop` - Gracefully stop the worker
  """
  @type command :: :replan | :pause | :resume | :reset | :stop
  @doc """
  Starts a worker process linked to the current process.

  ## Options

    * `:agent` - Agent struct or module implementing agent behavior (required)
    * `:pubsub` - PubSub module for event broadcasting (required)
    * `:topic` - Custom topic for events (optional, defaults to agent.id)
    * `:name` - Registration name (optional, defaults to agent.id)
    * `:max_queue_size` - Maximum queue size for commands (optional, defaults to 10000)

  ## Returns

    * `{:ok, pid}` - Successfully started worker
    * `{:error, reason}` - Failed to start worker

  ## Examples

      iex> Worker.start_link(agent: MyAgent.new(), pubsub: MyApp.PubSub)
      {:ok, #PID<0.123.0>}

      iex> Worker.start_link(
      ...>   agent: MyAgent.new(),
      ...>   pubsub: MyApp.PubSub,
      ...>   topic: "custom.topic",
      ...>   name: "worker_1"
      ...> )
      {:ok, #PID<0.124.0>}
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    debug("Starting worker", opts: opts)
    agent_input = Keyword.fetch!(opts, :agent)

    agent =
      if is_atom(agent_input) and :erlang.function_exported(agent_input, :new, 0) do
        agent_input.new()
      else
        agent_input
      end

    name = opts[:name] || agent.id
    pubsub = Keyword.fetch!(opts, :pubsub)
    topic = Keyword.get(opts, :topic)
    max_queue_size = Keyword.get(opts, :max_queue_size, @default_max_queue_size)

    debug("Initializing worker", name: name, pubsub: pubsub, topic: topic)

    GenServer.start_link(
      __MODULE__,
      %{agent: agent, pubsub: pubsub, topic: topic, max_queue_size: max_queue_size},
      name: via_tuple(name)
    )
  end

  @doc """
  Returns a child specification for starting the worker under a supervisor.

  ## Options

  Accepts same options as `start_link/1` plus:
    * `:id` - Optional supervisor child id (defaults to module name)

  ## Examples

      children = [
        {Worker, agent: agent, pubsub: pubsub, id: :worker_1}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    debug("Creating child spec", opts: opts)
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: 5000,
      restart: :permanent,
      type: :worker
    }
  end

  @doc """
  Sends an asynchronous action command to the worker.

  The command is processed based on the worker's current state:
  - If :running or :idle - Executed immediately
  - If :paused - Queued for later execution
  - Otherwise - Returns error

  ## Parameters

    * `server` - Worker pid or name
    * `attrs` - Map of command attributes including :command key

  ## Examples

      iex> Worker.act(worker, %{command: :move, destination: :kitchen})
      :ok

      iex> Worker.act(worker, %{command: :recharge})
      :ok
  """
  @spec act(GenServer.server(), map()) :: :ok
  def act(server, attrs) do
    debug("Received act command", server: server, attrs: attrs)

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.act",
        source: "/agent/act",
        data: attrs
      })

    GenServer.cast(server, signal)
  end

  @doc """
  Sends a synchronous management command to the worker.

  ## Parameters

    * `server` - Worker pid or name
    * `command` - Management command (see @type command)
    * `args` - Optional arguments for the command

  ## Returns

    * `{:ok, state}` - Command processed successfully
    * `{:error, reason}` - Command failed

  ## Examples

      iex> Worker.manage(worker, :pause)
      {:ok, %State{status: :paused}}

      iex> Worker.manage(worker, :resume)
      {:ok, %State{status: :running}}
  """
  @spec manage(GenServer.server(), command(), term()) :: {:ok, State.t()} | {:error, term()}
  def manage(server, command, args \\ nil) do
    debug("Received manage command", server: server, command: command, args: args)

    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.manage",
        source: "/agent/manage",
        data: %{command: command, args: args}
      })

    GenServer.call(server, signal)
  end

  # Server Callbacks

  @impl true
  def init(%{agent: agent, pubsub: pubsub, topic: topic, max_queue_size: max_queue_size}) do
    debug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    state = %State{
      agent: agent,
      pubsub: pubsub,
      topic: topic || State.default_topic(agent.id),
      status: :initializing,
      max_queue_size: max_queue_size
    }

    with :ok <- validate_state(state),
         :ok <- subscribe_to_topic(state),
         {:ok, running_state} <- State.transition(state, :idle) do
      emit(running_state, :started, %{agent_id: agent.id})
      debug("Worker initialized successfully", state: running_state)
      {:ok, running_state}
    else
      {:error, reason} ->
        error("Failed to initialize worker", reason: reason)
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast(%Signal{type: "jido.agent.act", data: attrs}, state) do
    debug("Handling act signal", attrs: attrs, state: state)

    case process_act(attrs, state) do
      {:ok, new_state} ->
        debug("Act processed successfully", new_state: new_state)
        {:noreply, process_pending_commands(new_state)}

      {:error, :queue_overflow} ->
        debug("Act dropped due to queue overflow")
        {:noreply, state}

      {:error, reason} ->
        error("Failed to process act", reason: reason)
        {:noreply, state}
    end
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(
        %Signal{type: "jido.agent.manage", data: %{command: cmd, args: args}},
        from,
        state
      ) do
    debug("Handling manage signal", command: cmd, args: args, from: from)

    case process_manage(cmd, args, from, state) do
      {:ok, new_state} ->
        debug("Manage command processed successfully", new_state: new_state)
        {:reply, {:ok, new_state}, process_pending_commands(new_state)}

      {:error, reason} ->
        error("Failed to process manage command", reason: reason)
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(_msg, _from, state), do: {:reply, {:error, :invalid_command}, state}

  @impl true
  def handle_info(%Signal{} = signal, state) do
    debug("Handling info signal", signal: signal)

    case process_signal(signal, state) do
      {:ok, new_state} ->
        debug("Signal processed successfully", new_state: new_state)
        {:noreply, process_pending_commands(new_state)}

      :ignore ->
        debug("Signal ignored")
        {:noreply, state}

      {:error, reason} ->
        error("Failed to process signal", reason: reason)

        Logger.warning("Invalid signal received",
          signal: signal,
          reason: reason,
          agent_id: state.agent.id
        )

        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private Methods
  private do
    defp process_signal(%Signal{type: "jido.agent.act", data: data}, state) do
      debug("Processing act signal", data: data)
      process_act(data, state)
    end

    defp process_signal(
           %Signal{type: "jido.agent.manage", data: %{command: cmd, args: args}},
           state
         ) do
      debug("Processing manage signal", command: cmd, args: args)
      process_manage(cmd, args, nil, state)
    end

    defp process_signal(_signal, _state), do: :ignore

    defp process_act(attrs, state) do
      case state.status do
        :paused ->
          debug("Queueing act while paused", attrs: attrs)

          case queue_command(state, {:act, attrs}) do
            {:ok, new_state} -> {:ok, new_state}
            {:error, :queue_overflow} = error -> error
          end

        status when status in [:idle, :running] ->
          debug("Processing act in #{status} state", attrs: attrs)

          with {:ok, running_state} <- ensure_running_state(state),
               {:ok, new_agent} <- execute_action(running_state, attrs),
               {:ok, idle_state} <- State.transition(%{running_state | agent: new_agent}, :idle) do
            emit(idle_state, :act_completed, %{
              initial_state: state.agent,
              final_state: new_agent
            })

            {:ok, idle_state}
          end

        _ ->
          {:error, {:invalid_state, state.status}}
      end
    end

    defp process_manage(:pause, _args, _from, %{status: status} = state) do
      debug("Pausing agent")

      case status do
        :running ->
          with {:ok, paused_state} <- State.transition(state, :paused) do
            emit(paused_state, :state_changed, %{from: :running, to: :paused})
            {:ok, paused_state}
          end

        _ ->
          {:error, {:invalid_state, status}}
      end
    end

    defp process_manage(:resume, _args, _from, %{status: status} = state) do
      debug("Resuming agent")

      case status do
        status when status in [:idle, :paused] ->
          with {:ok, running_state} <- State.transition(state, :running) do
            emit(running_state, :state_changed, %{from: status, to: :running})

            # Process any pending commands while in idle state
            idle_state = %{running_state | status: :idle}
            processed_state = process_pending_commands(idle_state)

            # Return to running state after processing commands
            case State.transition(processed_state, :running) do
              {:ok, final_running_state} ->
                {:ok, final_running_state}

              error ->
                error
            end
          end

        _ ->
          {:error, {:invalid_state, status}}
      end
    end

    defp process_manage(:reset, _args, _from, state) do
      debug("Resetting agent")

      with {:ok, idle_state} <- State.transition(state, :idle) do
        emit(idle_state, :state_changed, %{from: state.status, to: :idle})
        {:ok, %{idle_state | pending: :queue.new()}}
      end
    end

    defp process_manage(cmd, _args, _from, _state) do
      error("Invalid manage command", command: cmd)
      {:error, :invalid_command}
    end

    defp process_pending_commands(%{status: :idle, pending: queue} = state) do
      case :queue.out(queue) do
        {{:value, {:act, attrs}}, new_queue} ->
          state_with_new_queue = %{state | pending: new_queue}

          case process_act(attrs, state_with_new_queue) do
            {:ok, new_state} -> process_pending_commands(new_state)
            {:error, _reason} -> state_with_new_queue
          end

        {:empty, _} ->
          state
      end
    end

    defp process_pending_commands(state), do: state

    defp execute_action(%{status: status} = _state, _attrs) when status != :running do
      {:error, {:invalid_state, status}}
    end

    defp execute_action(%{status: :running} = state, %{command: command} = attrs) do
      params = Map.delete(attrs, :command)
      state.agent.__struct__.act(state.agent, command, params)
    end

    defp execute_action(%{status: :running} = state, attrs) do
      state.agent.__struct__.act(state.agent, :default, attrs)
    end

    defp ensure_running_state(%{status: :idle} = state) do
      with {:ok, running_state} <- State.transition(state, :running) do
        emit(running_state, :state_changed, %{from: :idle, to: :running})
        {:ok, running_state}
      end
    end

    defp ensure_running_state(%{status: :running} = state), do: {:ok, state}

    defp validate_state(%State{pubsub: nil}), do: {:error, "PubSub module is required"}
    defp validate_state(%State{agent: nil}), do: {:error, "Agent is required"}
    defp validate_state(_state), do: :ok

    defp queue_command(state, command) do
      queue_size = :queue.len(state.pending)

      if queue_size >= state.max_queue_size do
        debug("Queue overflow, dropping command",
          queue_size: queue_size,
          max_size: state.max_queue_size
        )

        emit(state, :queue_overflow, %{
          queue_size: queue_size,
          max_size: state.max_queue_size,
          dropped_command: command
        })

        {:error, :queue_overflow}
      else
        {:ok, %{state | pending: :queue.in(command, state.pending)}}
      end
    end

    defp subscribe_to_topic(%State{pubsub: pubsub, topic: topic}) do
      debug("Subscribing to topic", pubsub: pubsub, topic: topic)
      Phoenix.PubSub.subscribe(pubsub, topic)
    end

    defp emit(%State{} = state, event_type, payload) do
      debug("Emitting event", type: event_type, payload: payload)

      {:ok, signal} =
        Signal.new(%{
          type: "jido.agent.#{event_type}",
          source: "/agent/#{state.agent.id}",
          data: payload
        })

      Phoenix.PubSub.broadcast(state.pubsub, state.topic, signal)
    end

    defp via_tuple(name), do: {:via, Registry, {Jido.AgentRegistry, name}}
  end
end
