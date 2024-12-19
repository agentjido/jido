defmodule Jido.Agent.Worker do
  @moduledoc """
  A GenServer implementation for managing Jido agents with centralized command handling
  and pluggable communication.

  This module provides a robust worker process for Jido agents, handling:
  - Agent state management
  - Command processing and queueing
  - PubSub-based communication
  - Metrics and signal emission

  It supports various commands like replan, pause, resume, reset, and stop,
  and manages the agent's lifecycle through different states:

  - idle: Initial state, waiting for commands. Can transition to planning.
  - planning: Agent is formulating its next actions. Can transition to running or idle.
  - running: Agent is actively executing its plan. Can transition to paused or idle.
  - paused: Agent execution is temporarily suspended. Can transition to running or idle.

  State transitions are triggered by commands:
  - replan: idle -> planning -> running
  - pause: running -> paused
  - resume: paused -> running
  - reset/stop: any state -> idle
  """

  use GenServer
  use Jido.Util, debug_enabled: true
  alias Jido.Signal
  alias Jido.Agent.Worker.State
  require Logger

  @type command :: :replan | :pause | :resume | :reset | :stop

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
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

    GenServer.start_link(
      __MODULE__,
      %{agent: agent, pubsub: pubsub, topic: topic},
      name: via_tuple(name)
    )
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
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
    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.act",
        source: "/agent/#{server}",
        data: attrs
      })

    GenServer.cast(server, signal)
  end

  @spec manage(GenServer.server(), command(), term()) :: {:ok, State.t()} | {:error, term()}
  def manage(server, command, args \\ nil) do
    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.manage",
        source: "/agent/#{server}",
        data: %{command: command, args: args}
      })

    GenServer.call(server, signal)
  end

  # Server Callbacks

  @impl true
  @spec init(map()) :: {:ok, State.t()} | {:stop, term()}
  def init(%{agent: agent, pubsub: pubsub, topic: topic}) do
    state = %State{
      agent: agent,
      pubsub: pubsub,
      topic: topic || State.default_topic(agent.id)
    }

    with :ok <- validate_state(state),
         :ok <- subscribe_to_topic(state) do
      emit(state, :started, %{agent_id: agent.id})
      {:ok, state}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_cast(%Signal{type: "jido.agent.act", data: attrs}, state) do
    case process_act(attrs, state) do
      {:ok, new_state} -> {:noreply, process_pending_commands(new_state)}
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_cast(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call(
        %Signal{type: "jido.agent.manage", data: %{command: cmd, args: args}},
        from,
        state
      ) do
    case process_manage(cmd, args, from, state) do
      {:ok, new_state} -> {:reply, {:ok, new_state}, process_pending_commands(new_state)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(_msg, _from, state), do: {:reply, {:error, :invalid_command}, state}

  @impl true
  def handle_info(%Signal{} = signal, state) do
    case process_signal(signal, state) do
      {:ok, new_state} ->
        {:noreply, process_pending_commands(new_state)}

      :ignore ->
        {:noreply, state}

      {:error, reason} ->
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
  defp process_signal(%Signal{type: "jido.agent.act", data: data}, state) do
    process_act(data, state)
  end

  defp process_signal(
         %Signal{type: "jido.agent.manage", data: %{command: cmd, args: args}},
         state
       ) do
    process_manage(cmd, args, nil, state)
  end

  defp process_signal(_signal, _state), do: :ignore

  defp process_act(attrs, %{status: :paused} = state) do
    {:ok, signal} =
      Signal.new(%{
        type: "jido.agent.act",
        source: "/agent/#{state.agent.id}",
        data: attrs
      })

    {:ok, %{state | pending: :queue.in(signal, state.pending)}}
  end

  defp process_act(attrs, %{status: status} = state) when status in [:idle, :running] do
    with {:ok, new_agent} <- state.agent.__struct__.act(state.agent, attrs) do
      emit(state, :act_completed, %{initial_state: state.agent, final_state: new_agent})
      {:ok, %{state | agent: new_agent, status: :idle}}
    end
  end

  defp process_manage(:resume, _args, _from, %{status: :paused} = state) do
    {:ok, %{state | status: :running}}
  end

  defp process_pending_commands(%{status: :idle} = state) do
    case :queue.out(state.pending) do
      {{:value, signal}, new_queue} ->
        case process_signal(signal, %{state | pending: new_queue}) do
          {:ok, new_state} -> process_pending_commands(new_state)
          _ -> %{state | pending: new_queue}
        end

      {:empty, _} ->
        state
    end
  end

  defp process_pending_commands(state), do: state

  defp validate_state(%State{pubsub: nil}), do: {:error, "PubSub module is required"}
  defp validate_state(%State{agent: nil}), do: {:error, "Agent is required"}
  defp validate_state(_state), do: :ok

  defp subscribe_to_topic(%State{pubsub: pubsub, topic: topic}),
    do: Phoenix.PubSub.subscribe(pubsub, topic)

  defp emit(%State{} = state, event_type, payload) do
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
