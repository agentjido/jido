defmodule Jido.Agent.Worker.State do
  use TypedStruct
  require Logger

  typedstruct do
    field(:agent, Jido.Agent.t(), enforce: true)
    field(:pubsub, module(), enforce: true)
    field(:topic, String.t(), enforce: true)
    field(:status, status(), default: :idle)
    field(:pending, :queue.queue(), default: :queue.new())
  end

  @type status :: :initializing | :idle | :planning | :running | :paused

  # Define valid state transitions and their conditions
  @transitions %{
    initializing: %{
      idle: :initialization_complete
    },
    idle: %{
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

  def default_topic(agent_id) do
    "jido.agent.#{agent_id}"
  end
end
