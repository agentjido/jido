defmodule Jido.Agents.IteratorAgent do
  @moduledoc """
  A sample agent that demonstrates Chain of Thought behavior using the enhanced Iterator action.
  This agent can start an iteration sequence that executes a body action at each step
  and uses a decision action to control the iteration flow.
  """

  use Jido.Agent,
    name: "IteratorAgent",
    actions: [
      Jido.Actions.Iterator,
      Jido.Actions.CounterBody,
      Jido.Actions.LimitDecision
    ]

  @doc """
  Start a simple iteration with basic step counting (backward compatibility).
  """
  def start_simple_iteration(agent, max_steps \\ 10) do
    # Use CounterBody as a simple body action that just counts
    params = %{
      max_steps: max_steps,
      body_action: Jido.Actions.CounterBody,
      body_params: %{increment: 1},
      state_path: [:iterator_state]
    }

    cmd(agent, {Jido.Actions.Iterator, params}, %{}, runner: Jido.Runner.Simple)
  end

  @doc """
  Start an advanced iteration with a custom body action and decision action.
  """
  def start_advanced_iteration(agent, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, 10)
    body_action = Keyword.get(opts, :body_action, Jido.Actions.CounterBody)
    body_params = Keyword.get(opts, :body_params, %{increment: 1})
    decision_action = Keyword.get(opts, :decision_action, Jido.Actions.LimitDecision)
    decision_params = Keyword.get(opts, :decision_params, %{count_limit: 50})
    state_path = Keyword.get(opts, :state_path, [:iterator_state])

    params = %{
      max_steps: max_steps,
      body_action: body_action,
      body_params: body_params,
      decision_action: decision_action,
      decision_params: decision_params,
      state_path: state_path
    }

    cmd(agent, {Jido.Actions.Iterator, params}, %{}, runner: Jido.Runner.Simple)
  end

  @doc """
  Start a counting iteration that stops when a certain count is reached.
  """
  def start_counting_iteration(agent, count_limit \\ 25, increment \\ 2) do
    params = %{
      max_steps: 100, # Safety limit
      body_action: Jido.Actions.CounterBody,
      body_params: %{increment: increment},
      decision_action: Jido.Actions.LimitDecision,
      decision_params: %{count_limit: count_limit},
      state_path: [:iterator_state]
    }

    cmd(agent, {Jido.Actions.Iterator, params}, %{}, runner: Jido.Runner.Simple)
  end

  # Backward compatibility alias
  def start_iteration(agent, max_steps \\ 10) do
    start_simple_iteration(agent, max_steps)
  end
end
