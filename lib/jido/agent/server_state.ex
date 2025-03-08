defmodule Jido.Agent.Server.State do
  @moduledoc """
  Defines the state management structure and transition logic for Agent Servers.

  The Server.State module implements a finite state machine (FSM) that governs
  the lifecycle of agent workers in the Jido system. It ensures type safety and
  enforces valid state transitions while providing telemetry and logging for
  observability.

  ## State Machine

  The worker can be in one of the following states:
  - `:initializing` - Initial state when worker is starting up
  - `:idle` - Server is inactive and ready to accept new commands
  - `:planning` - Server is planning but not yet executing actions
  - `:running` - Server is actively executing commands
  - `:paused` - Server execution is temporarily suspended

  ## State Transitions

  Valid state transitions are:
  ```
  initializing -> idle        (initialization_complete)
  idle         -> planning    (plan_initiated)
  idle         -> running     (direct_execution)
  planning     -> running     (plan_completed)
  planning     -> idle        (plan_cancelled)
  running      -> paused      (execution_paused)
  running      -> idle        (execution_completed)
  paused       -> running     (execution_resumed)
  paused       -> idle        (execution_cancelled)
  ```

  ## Fields

  - `:agent` - The Agent struct being managed by this worker (required)
  - `:pubsub` - PubSub module for event broadcasting (required)
  - `:topic` - PubSub topic for worker events (required)
  - `:subscriptions` - List of subscribed topics (default: [])
  - `:status` - Current state of the worker (default: :idle)
  - `:pending_signals` - Queue of pending signals awaiting execution
  - `:max_queue_size` - Maximum number of commands that can be queued (default: 10000)
  - `:child_supervisor` - Dynamic supervisor PID for managing child processes

  ## Example

      iex> state = %Server.State{
      ...>   agent: my_agent,
      ...>   pubsub: MyApp.PubSub,
      ...>   topic: "agent.worker.1",
      ...>   status: :idle
      ...> }
      iex> {:ok, new_state} = Server.State.transition(state, :running)
      iex> new_state.status
      :running
  """

  use TypedStruct
  use ExDbug, enabled: false
  alias Jido.Signal
  alias Jido.Agent.Server.Signal, as: ServerSignal
  alias Jido.Agent.Server.Output, as: ServerOutput
  alias Jido.Signal.Dispatch

  @typedoc """
  Represents the possible states of a worker.

  - `:initializing` - Server is starting up
  - `:idle` - Server is inactive
  - `:planning` - Server is planning actions
  - `:running` - Server is executing actions
  - `:paused` - Server execution is suspended
  """
  @type status :: :initializing | :idle | :planning | :running | :paused
  @type modes :: :auto | :step
  @type log_levels ::
          :debug | :info | :notice | :warning | :error | :critical | :alert | :emergency
  @type dispatch_config :: [
          out: Dispatch.dispatch_config(),
          log: Dispatch.dispatch_config(),
          err: Dispatch.dispatch_config()
        ]

  typedstruct do
    # Original opts the Agent was created with
    field(:opts, keyword(), default: [])

    # The Agent struct being managed by this worker
    field(:agent, Jido.Agent.t(), enforce: true)

    # The mode of the worker, execute signals automatically or force step-by-step
    field(:mode, modes(), default: :auto)

    # The log level of the worker
    field(:log_level, log_levels(), default: :info)

    # The maximum size of the pending signals queue
    field(:max_queue_size, non_neg_integer(), default: 10_000)

    # The registry of the agent
    field(:registry, atom(), default: Jido.Agent.Registry)

    # The dispatch configuration for the worker
    field(:dispatch, dispatch_config(), default: {:logger, []})

    # The router of the worker
    field(:router, Jido.Signal.Router.Router.t(), default: Jido.Signal.Router.new!())
    field(:journal, Jido.Signal.Journal.t(), default: nil)

    # Skills to compose capabilities into the Agent
    field(:skills, [Jido.Skill.t()], default: [])

    # Pids for the local supervisor, parent and
    field(:child_supervisor, pid())
    field(:parent_pid, pid())
    field(:orchestrator_pid, pid())

    # Runtime status
    field(:status, status(), default: :idle)
    field(:pending_signals, :queue.queue(), default: :queue.new())
    field(:current_signal_type, atom(), default: nil)
    field(:current_signal, Jido.Signal.t(), default: nil)
    field(:reply_refs, %{String.t() => GenServer.from()}, default: %{})
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
  def transition(%__MODULE__{status: current} = state, current) do
    dbug("State already in desired state - no transition needed", current: current)
    {:ok, state}
  end

  def transition(%__MODULE__{status: current} = state, desired) do
    dbug("Attempting state transition", current: current, desired: desired)

    case @transitions[current][desired] do
      nil ->
        dbug("Invalid state transition", current: current, desired: desired)

        :transition_failed
        |> ServerSignal.event_signal(state, %{from: current, to: desired})
        |> ServerOutput.emit()

        {:error, {:invalid_transition, current, desired}}

      _reason ->
        dbug("Valid state transition", current: current, desired: desired, reason: _reason)

        :transition_succeeded
        |> ServerSignal.event_signal(state, %{from: current, to: desired})
        |> ServerOutput.emit()

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
    dbug("Attempting to enqueue signal", signal: signal)
    queue_size = :queue.len(state.pending_signals)
    dbug("Current queue size", size: queue_size, max_size: state.max_queue_size)

    if queue_size >= state.max_queue_size do
      dbug("Queue overflow detected", queue_size: queue_size, max_size: state.max_queue_size)

      :queue_overflow
      |> ServerSignal.event_signal(state, %{
        queue_size: queue_size,
        max_size: state.max_queue_size
      })
      |> ServerOutput.emit()

      {:error, :queue_overflow}
    else
      dbug("Enqueuing signal", signal: signal)
      {:ok, %{state | pending_signals: :queue.in(signal, state.pending_signals)}}
    end
  end

  @doc """
  Enqueues a signal at the front of the state's pending signals queue.

  Validates that the queue size is within the configured maximum before adding.
  Emits a queue_overflow event if the queue is full.

  ## Parameters

  - `state` - Current server state
  - `signal` - Signal to enqueue at front

  ## Returns

  - `{:ok, new_state}` - Signal was successfully enqueued at front
  - `{:error, :queue_overflow}` - Queue is at max capacity

  ## Examples

      iex> state = %Server.State{pending_signals: :queue.new(), max_queue_size: 2}
      iex> Server.State.enqueue_front(state, %Signal{type: "test"})
      {:ok, %Server.State{pending_signals: updated_queue}}

      iex> state = %Server.State{pending_signals: full_queue, max_queue_size: 1}
      iex> Server.State.enqueue_front(state, %Signal{type: "test"})
      {:error, :queue_overflow}
  """
  @spec enqueue_front(%__MODULE__{}, Signal.t()) ::
          {:ok, %__MODULE__{}} | {:error, :queue_overflow}
  def enqueue_front(%__MODULE__{} = state, %Signal{} = signal) do
    dbug("Attempting to enqueue signal at front", signal: signal)
    queue_size = :queue.len(state.pending_signals)
    dbug("Current queue size", size: queue_size, max_size: state.max_queue_size)

    if queue_size >= state.max_queue_size do
      dbug("Queue overflow detected", queue_size: queue_size, max_size: state.max_queue_size)

      :queue_overflow
      |> ServerSignal.event_signal(state, %{
        queue_size: queue_size,
        max_size: state.max_queue_size
      })
      |> ServerOutput.emit()

      {:error, :queue_overflow}
    else
      dbug("Enqueuing signal at front", signal: signal)
      {:ok, %{state | pending_signals: :queue.in_r(signal, state.pending_signals)}}
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
    dbug("Attempting to dequeue signal")

    case :queue.out(state.pending_signals) do
      {{:value, signal}, new_queue} ->
        dbug("Signal dequeued successfully", signal: signal)

        {:ok, signal,
         %{
           state
           | pending_signals: new_queue,
             current_signal: signal
         }}

      {:empty, _} ->
        dbug("Queue is empty")
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
    dbug("Clearing signal queue", queue_size: :queue.len(state.pending_signals))

    :queue_cleared
    |> ServerSignal.event_signal(state, %{
      queue_size: :queue.len(state.pending_signals)
    })
    |> ServerOutput.emit()

    {:ok, %{state | pending_signals: :queue.new()}}
  end

  @doc """
  Checks the current size of the pending signals queue.

  Returns the queue size as an integer if within limits, or :queue_overflow error if exceeded.

  ## Parameters

  - `state` - Current server state

  ## Returns

  - `{:ok, size}` - Current queue size as integer
  - `{:error, :queue_overflow}` - Queue size exceeds maximum

  ## Examples

      iex> state = %Server.State{pending_signals: queue_with_items, max_queue_size: 100}
      iex> Server.State.check_queue_size(state)
      {:ok, 5}

      iex> state = %Server.State{pending_signals: large_queue, max_queue_size: 10}
      iex> Server.State.check_queue_size(state)
      {:error, :queue_overflow}
  """
  @spec check_queue_size(%__MODULE__{}) :: {:ok, non_neg_integer()} | {:error, :queue_overflow}
  def check_queue_size(%__MODULE__{} = state) do
    dbug("Checking queue size")
    queue_size = :queue.len(state.pending_signals)
    dbug("Current queue metrics", size: queue_size, max_size: state.max_queue_size)

    if queue_size > state.max_queue_size do
      dbug("Queue size exceeds maximum", queue_size: queue_size, max_size: state.max_queue_size)

      :queue_overflow
      |> ServerSignal.event_signal(state, %{
        queue_size: queue_size,
        max_size: state.max_queue_size
      })
      |> ServerOutput.emit()

      {:error, :queue_overflow}
    else
      dbug("Queue size within limits", size: queue_size)
      {:ok, queue_size}
    end
  end

  @doc """
  Stores a reply reference for a signal.

  ## Parameters

  - `state` - Current server state
  - `signal_id` - ID of the signal to store ref for
  - `from` - GenServer.from() tuple to store

  ## Returns

  Updated state with stored reply ref
  """
  @spec store_reply_ref(%__MODULE__{}, String.t(), GenServer.from()) :: %__MODULE__{}
  def store_reply_ref(%__MODULE__{} = state, signal_id, from) do
    dbug("Storing reply ref", signal_id: signal_id, from: from)
    %{state | reply_refs: Map.put(state.reply_refs, signal_id, from)}
  end

  @doc """
  Retrieves a stored reply reference for a signal.

  ## Parameters

  - `state` - Current server state
  - `signal_id` - ID of the signal to get ref for

  ## Returns

  The stored GenServer.from() tuple or nil if not found
  """
  @spec get_reply_ref(%__MODULE__{}, String.t()) :: GenServer.from() | nil
  def get_reply_ref(%__MODULE__{} = state, signal_id) do
    dbug("Getting reply ref", signal_id: signal_id)
    Map.get(state.reply_refs, signal_id)
  end

  @doc """
  Removes a stored reply reference for a signal.

  ## Parameters

  - `state` - Current server state
  - `signal_id` - ID of the signal to remove ref for

  ## Returns

  Updated state with reply ref removed
  """
  @spec remove_reply_ref(%__MODULE__{}, String.t()) :: %__MODULE__{}
  def remove_reply_ref(%__MODULE__{} = state, signal_id) do
    dbug("Removing reply ref", signal_id: signal_id)
    %{state | reply_refs: Map.delete(state.reply_refs, signal_id)}
  end
end
