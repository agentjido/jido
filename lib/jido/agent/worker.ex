defmodule Jido.Agent.Worker do
  use GenServer
  use Private
  use Jido.Util, debug_enabled: true
  alias Jido.Signal
  alias Jido.Agent.Worker.State
  require Logger

  @type command :: :replan | :pause | :resume | :reset | :stop

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

    debug("Initializing worker", name: name, pubsub: pubsub, topic: topic)

    GenServer.start_link(
      __MODULE__,
      %{agent: agent, pubsub: pubsub, topic: topic},
      name: via_tuple(name)
    )
  end

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
  def init(%{agent: agent, pubsub: pubsub, topic: topic}) do
    debug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    state = %State{
      agent: agent,
      pubsub: pubsub,
      topic: topic || State.default_topic(agent.id),
      status: :initializing
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
          queue_command(state, {:act, attrs})

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
      {:ok, %{state | pending: :queue.in(command, state.pending)}}
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
