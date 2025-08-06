defmodule Jido.Actions.CounterBody do
  @moduledoc """
  Example body action for the Iterator that increments a counter.
  Demonstrates how to build actions that work as iterator bodies.
  """

  use Jido.Action,
    name: "counter_body",
    description: "Increments a counter value, designed for use with Iterator",
    schema: [
      step: [type: :integer, doc: "Current iteration step"],
      run_id: [type: :string, doc: "Iterator run ID"],
      iterator_state: [type: :map, doc: "State passed from iterator"],
      increment: [type: :integer, default: 1, doc: "Amount to increment by"]
    ]

  @impl true
  def run(params, _context) do
    step = params[:step] || 0
    run_id = params[:run_id]
    iterator_state = params[:iterator_state] || %{}
    increment = params[:increment] || 1

    # Get current counter value from iterator state
    current_count = iterator_state[:count] || 0
    new_count = current_count + increment

    result = %{
      step: step,
      run_id: run_id,
      previous_count: current_count,
      new_count: new_count,
      increment: increment,
      message: "Step #{step}: count increased from #{current_count} to #{new_count}"
    }

    # Return result that will be merged into iterator state
    {:ok, %{count: new_count, counter_history: result}}
  end
end
