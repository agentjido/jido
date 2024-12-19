defmodule Jido.Agent.Worker.State do
  @moduledoc """
  Defines the state management structure and transition logic for Agent Workers.

  The Worker.State module implements a finite state machine (FSM) that governs
  the lifecycle of agent workers in the Jido system. It ensures type safety and
  enforces valid state transitions while providing telemetry and logging for
  observability.

  ## State Machine

  The worker can be in one of the following states:
  - `:initializing` - Initial state when worker is starting up
  - `:idle` - Worker is inactive and ready to accept new commands
  - `:planning` - Worker is planning but not yet executing actions
  - `:running` - Worker is actively executing commands
  - `:paused` - Worker execution is temporarily suspended

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
  - `:status` - Current state of the worker (default: :idle)
  - `:pending` - Queue of pending commands awaiting execution

  ## Example

      iex> state = %Worker.State{
      ...>   agent: my_agent,
      ...>   pubsub: MyApp.PubSub,
      ...>   topic: "agent.worker.1",
      ...>   status: :idle
      ...> }
      iex> {:ok, new_state} = Worker.State.transition(state, :running)
      iex> new_state.status
      :running
  """

  use TypedStruct
  require Logger

  @typedoc """
  Represents the possible states of a worker.

  - `:initializing` - Worker is starting up
  - `:idle` - Worker is inactive
  - `:planning` - Worker is planning actions
  - `:running` - Worker is executing actions
  - `:paused` - Worker execution is suspended
  """
  @type status :: :initializing | :idle | :planning | :running | :paused

  typedstruct do
    field(:agent, Jido.Agent.t(), enforce: true)
    field(:pubsub, module(), enforce: true)
    field(:topic, String.t(), enforce: true)
    field(:status, status(), default: :idle)
    field(:pending, :queue.queue(), default: :queue.new())
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

  - `state` - Current Worker.State struct
  - `desired` - Desired target state

  ## Returns

  - `{:ok, new_state}` - Transition was successful
  - `{:error, {:invalid_transition, current, desired}}` - Invalid state transition

  ## Examples

      iex> state = %Worker.State{status: :idle}
      iex> Worker.State.transition(state, :running)
      {:ok, %Worker.State{status: :running}}

      iex> state = %Worker.State{status: :idle}
      iex> Worker.State.transition(state, :paused)
      {:error, {:invalid_transition, :idle, :paused}}
  """
  @spec transition(%__MODULE__{status: status()}, status()) ::
          {:ok, %__MODULE__{}} | {:error, {:invalid_transition, status(), status()}}
  def transition(%__MODULE__{status: current} = state, desired) do
    case @transitions[current][desired] do
      nil ->
        {:error, {:invalid_transition, current, desired}}

      reason ->
        Logger.debug(
          "Agent state transition from #{current} to #{desired} (#{reason}) for agent #{state.agent.id}"
        )

        {:ok, %{state | status: desired}}
    end
  end

  @doc """
  Generates the default PubSub topic name for an agent.

  ## Parameters

  - `agent_id` - Unique identifier of the agent

  ## Returns

  String in the format "jido.agent.<agent_id>"

  ## Examples

      iex> Worker.State.default_topic("robot_1")
      "jido.agent.robot_1"
  """
  @spec default_topic(String.t()) :: String.t()
  def default_topic(agent_id) when is_binary(agent_id) do
    "jido.agent.#{agent_id}"
  end
end
