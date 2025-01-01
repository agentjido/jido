defmodule Jido.Agent.Server.State do
  @moduledoc false
  # Defines the state management structure and transition logic for Agent Servers.

  # The Server.State module implements a finite state machine (FSM) that governs
  # the lifecycle of agent workers in the Jido system. It ensures type safety and
  # enforces valid state transitions while providing telemetry and logging for
  # observability.

  ## State Machine

  # The worker can be in one of the following states:
  # - `:initializing` - Initial state when worker is starting up
  # - `:idle` - Server is inactive and ready to accept new commands
  # - `:planning` - Server is planning but not yet executing actions
  # - `:running` - Server is actively executing commands
  # - `:paused` - Server execution is temporarily suspended

  ## State Transitions

  # Valid state transitions are:
  # ```
  # initializing -> idle        (initialization_complete)
  # idle         -> planning    (plan_initiated)
  # idle         -> running     (direct_execution)
  # planning     -> running     (plan_completed)
  # planning     -> idle        (plan_cancelled)
  # running      -> paused      (execution_paused)
  # running      -> idle        (execution_completed)
  # paused       -> running     (execution_resumed)
  # paused       -> idle        (execution_cancelled)
  # ```

  # ## Fields

  # - `:agent` - The Agent struct being managed by this worker (required)
  # - `:pubsub` - PubSub module for event broadcasting (required)
  # - `:topic` - PubSub topic for worker events (required)
  # - `:subscriptions` - List of subscribed topics (default: [])
  # - `:status` - Current state of the worker (default: :idle)
  # - `:pending_signals` - Queue of pending signals awaiting execution
  # - `:max_queue_size` - Maximum number of commands that can be queued (default: 10000)
  # - `:child_supervisor` - Dynamic supervisor PID for managing child processes

  ## Example

  #     iex> state = %Server.State{
  #     ...>   agent: my_agent,
  #     ...>   pubsub: MyApp.PubSub,
  #     ...>   topic: "agent.worker.1",
  #     ...>   status: :idle
  #     ...> }
  #     iex> {:ok, new_state} = Server.State.transition(state, :running)
  #     iex> new_state.status
  #     :running

  use TypedStruct
  require Logger
  alias Jido.Signal
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.PubSub
  use ExDbug, enabled: false

  @typedoc """
  Represents the possible states of a worker.

  - `:initializing` - Server is starting up
  - `:idle` - Server is inactive
  - `:planning` - Server is planning actions
  - `:running` - Server is executing actions
  - `:paused` - Server execution is suspended
  """
  @type status :: :initializing | :idle | :planning | :running | :paused

  @derive Jason.Encoder
  @derive Inspect
  typedstruct do
    field(:agent, Jido.Agent.t(), enforce: true)
    field(:pubsub, module())
    field(:topic, String.t())
    field(:subscriptions, [String.t()], default: [])
    field(:status, status(), default: :idle)
    field(:pending_signals, :queue.queue(), default: :queue.new())
    field(:max_queue_size, non_neg_integer(), default: 10_000)
    field(:child_supervisor, pid())
  end

  # Define valid state transitions and their conditions
  @transitions %{
    initializing: %{
      idle: :initialization_complete
    },
    idle: %{
      idle: :already_idle,
      planning: :plan_initiated,
      running: :direct_execution
    },
    planning: %{
      running: :plan_completed,
      idle: :plan_cancelled
    },
    running: %{
      paused: :execution_paused,
      idle: :execution_completed
    },
    paused: %{
      running: :execution_resumed,
      idle: :execution_cancelled
    }
  }

  @doc """
  Attempts to transition the worker to a new state.

  This function enforces the state machine rules defined in @transitions.
  It logs state transitions for debugging and monitoring purposes.

  ## Parameters

  - `state` - Current Server.State struct
  - `desired` - Desired target state

  ## Returns

  - `{:ok, new_state}` - Transition was successful
  - `{:error, {:invalid_transition, current, desired}}` - Invalid state transition

  ## Examples

      iex> state = %Server.State{status: :idle}
      iex> Server.State.transition(state, :running)
      {:ok, %Server.State{status: :running}}

      iex> state = %Server.State{status: :idle}
      iex> Server.State.transition(state, :paused)
      {:error, {:invalid_transition, :idle, :paused}}
  """
  @spec transition(%__MODULE__{status: status()}, status()) ::
          {:ok, %__MODULE__{}} | {:error, {:invalid_transition, status(), status()}}
  def transition(%__MODULE__{status: current} = state, desired) do
    case @transitions[current][desired] do
      nil ->
        PubSub.emit_event(state, ServerSignal.transition_failed(), from: current, to: desired)
        {:error, {:invalid_transition, current, desired}}

      _reason ->
        dbug(
          "Agent state transition from #{current} to #{desired} (#{reason}) for agent #{state.agent.id}"
        )

        PubSub.emit_event(state, ServerSignal.transition_succeeded(), from: current, to: desired)
        {:ok, %{state | status: desired}}
    end
  end

  @doc """
  Enqueues a signal into the state's pending signals queue.

  Validates that the queue size is within the configured maximum before adding.
  Emits a queue_overflow event if the queue is full.

  ## Parameters

  - `state` - Current server state
  - `signal` - Signal to enqueue

  ## Returns

  - `{:ok, new_state}` - Signal was successfully enqueued
  - `{:error, :queue_overflow}` - Queue is at max capacity

  ## Examples

      iex> state = %Server.State{pending_signals: :queue.new(), max_queue_size: 2}
      iex> Server.State.enqueue(state, %Signal{type: "test"})
      {:ok, %Server.State{pending_signals: updated_queue}}

      iex> state = %Server.State{pending_signals: full_queue, max_queue_size: 1}
      iex> Server.State.enqueue(state, %Signal{type: "test"})
      {:error, :queue_overflow}
  """
  @spec enqueue(%__MODULE__{}, Signal.t()) :: {:ok, %__MODULE__{}} | {:error, :queue_overflow}
  def enqueue(%__MODULE__{} = state, %Signal{} = signal) do
    queue_size = :queue.len(state.pending_signals)

    if queue_size >= state.max_queue_size do
      dbug(
        "Queue overflow, dropping signal",
        queue_size: queue_size,
        max_size: state.max_queue_size
      )

      PubSub.emit_event(state, ServerSignal.queue_overflow(),
        queue_size: queue_size,
        max_size: state.max_queue_size
      )

      {:error, :queue_overflow}
    else
      {:ok, %{state | pending_signals: :queue.in(signal, state.pending_signals)}}
    end
  end

  @doc """
  Dequeues a signal from the state's pending queue.

  Returns the next signal and updated state with the signal removed from the queue.
  Returns error if queue is empty.

  ## Parameters

  - `state` - Current server state

  ## Returns

  - `{:ok, signal, new_state}` - Signal was successfully dequeued
  - `{:error, :empty_queue}` - Queue is empty

  ## Examples

      iex> state = %Server.State{pending_signals: queue_with_items}
      iex> Server.State.dequeue(state)
      {:ok, %Signal{type: "test"}, %Server.State{pending_signals: updated_queue}}

      iex> state = %Server.State{pending_signals: :queue.new()}
      iex> Server.State.dequeue(state)
      {:error, :empty_queue}
  """
  @spec dequeue(%__MODULE__{}) :: {:ok, term(), %__MODULE__{}} | {:error, :empty_queue}
  def dequeue(%__MODULE__{} = state) do
    case :queue.out(state.pending_signals) do
      {{:value, signal}, new_queue} ->
        {:ok, signal, %{state | pending_signals: new_queue}}

      {:empty, _} ->
        {:error, :empty_queue}
    end
  end

  @doc """
  Empties the pending queue in the server state.

  Returns a new state with an empty queue.

  ## Parameters

  - `state` - Current server state

  ## Returns

  - `{:ok, new_state}` - Queue was successfully emptied

  ## Examples

      iex> state = %Server.State{pending_signals: queue_with_items}
      iex> Server.State.clear_queue(state)
      {:ok, %Server.State{pending_signals: :queue.new()}}
  """
  @spec clear_queue(%__MODULE__{}) :: {:ok, %__MODULE__{}}
  def clear_queue(%__MODULE__{} = state) do
    PubSub.emit_event(state, ServerSignal.queue_cleared(),
      queue_size: :queue.len(state.pending_signals)
    )

    {:ok, %{state | pending_signals: :queue.new()}}
  end

  def validate_state(%__MODULE__{agent: nil}), do: {:error, "Agent is required"}
  def validate_state(_state), do: :ok
end
