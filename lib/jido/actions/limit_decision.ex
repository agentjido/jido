defmodule Jido.Actions.LimitDecision do
  @moduledoc """
  Example decision action for the Iterator that stops when a limit is reached.
  Demonstrates how to build decision actions that control iteration flow.
  """

  use Jido.Action,
    name: "limit_decision",
    description: "Decides whether to continue iteration based on a limit",
    schema: [
      step: [type: :integer, doc: "Current iteration step"],
      max_steps: [type: :integer, doc: "Maximum steps allowed by iterator"],
      iterator_state: [type: :map, doc: "State passed from iterator"],
      count_limit: [type: :integer, default: 50, doc: "Stop when count reaches this limit"],
      step_limit: [type: :integer, doc: "Custom step limit (overrides max_steps if lower)"]
    ]

  @impl true
  def run(params, _context) do
    step = params[:step] || 0
    max_steps = params[:max_steps] || 10
    iterator_state = params[:iterator_state] || %{}
    count_limit = params[:count_limit] || 50
    step_limit = params[:step_limit]

    # Get current count from iterator state
    current_count = iterator_state[:count] || 0

    # Determine if we should continue
    continue_for_count = current_count < count_limit
    continue_for_steps = step + 1 < max_steps
    continue_for_custom_steps = if step_limit, do: step + 1 < step_limit, else: true

    should_continue = continue_for_count and continue_for_steps and continue_for_custom_steps

    # Determine termination reason if stopping
    termination_reason = cond do
      not continue_for_count -> :count_limit_reached
      not continue_for_steps -> :max_steps_reached  
      not continue_for_custom_steps -> :custom_step_limit_reached
      true -> :continuing
    end

    result = %{
      continue: should_continue,
      step: step,
      current_count: current_count,
      count_limit: count_limit,
      termination_reason: termination_reason,
      message: if should_continue do
        "Continue: count=#{current_count}, step=#{step}"
      else
        "Stop: #{termination_reason}, count=#{current_count}, step=#{step}"
      end
    }

    {:ok, result}
  end
end
