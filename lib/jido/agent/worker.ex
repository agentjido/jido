defmodule Jido.Agent.Worker do
  use GenServer
  use Private
  use Jido.Util, debug_enabled: false
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
  @spec init(map()) :: {:ok, State.t()} | {:stop, term()}
  def init(%{agent: agent, pubsub: pubsub, topic: topic}) do
    debug("Initializing state", agent: agent, pubsub: pubsub, topic: topic)

    state = %State{
      agent: agent,
      pubsub: pubsub,
      topic: topic || State.default_topic(agent.id)
    }

    with :ok <- validate_state(state),
         :ok <- subscribe_to_topic(state) do
      emit(state, :started, %{agent_id: agent.id})
      debug("Worker initialized successfully", state: state)
      {:ok, state}
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

    defp process_act(attrs, %{status: :paused} = state) do
      debug("Queueing act while paused", attrs: attrs)

      {:ok, signal} =
        Signal.new(%{
          type: "jido.agent.act",
          source: "/agent/#{state.agent.id}",
          data: attrs
        })

      {:ok, %{state | pending: :queue.in(signal, state.pending)}}
    end

    defp process_act(%{command: command} = attrs, %{status: status} = state)
         when status in [:idle, :running] do
      debug("Processing act in #{status} state", command: command, attrs: attrs)
      params = Map.delete(attrs, :command)

      with {:ok, new_agent} <- state.agent.__struct__.act(state.agent, command, params) do
        emit(state, :act_completed, %{initial_state: state.agent, final_state: new_agent})
        {:ok, %{state | agent: new_agent, status: :idle}}
      end
    end

    defp process_act(attrs, %{status: status} = state) when status in [:idle, :running] do
      debug("Processing act in #{status} state", attrs: attrs)
      # Default to :default command if none specified
      with {:ok, new_agent} <- state.agent.__struct__.act(state.agent, :default, attrs) do
        emit(state, :act_completed, %{initial_state: state.agent, final_state: new_agent})
        {:ok, %{state | agent: new_agent, status: :idle}}
      end
    end

    defp process_manage(:pause, _args, _from, state) do
      debug("Pausing agent")
      {:ok, %{state | status: :paused}}
    end

    defp process_manage(:resume, _args, _from, %{status: :paused} = state) do
      debug("Resuming from paused state")
      {:ok, %{state | status: :running}}
    end

    defp process_manage(:reset, _args, _from, state) do
      debug("Resetting agent state")
      {:ok, %{state | status: :idle, pending: :queue.new()}}
    end

    defp process_manage(cmd, _args, _from, _state) do
      error("Invalid manage command", command: cmd)
      {:error, :invalid_command}
    end

    defp process_pending_commands(%{status: :idle} = state) do
      debug("Processing pending commands", queue_length: :queue.len(state.pending))

      case :queue.out(state.pending) do
        {{:value, signal}, new_queue} ->
          debug("Processing next pending command", signal: signal)

          case process_signal(signal, %{state | pending: new_queue}) do
            {:ok, new_state} -> process_pending_commands(new_state)
            _ -> %{state | pending: new_queue}
          end

        {:empty, _} ->
          debug("No pending commands")
          state
      end
    end

    defp process_pending_commands(state), do: state

    defp validate_state(%State{pubsub: nil}), do: {:error, "PubSub module is required"}
    defp validate_state(%State{agent: nil}), do: {:error, "Agent is required"}
    defp validate_state(_state), do: :ok

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
