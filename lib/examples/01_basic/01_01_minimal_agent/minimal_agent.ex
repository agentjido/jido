defmodule Jido.Examples.MinimalAgent do
  @moduledoc """
  The smallest stateful Agent example.

  The route defaults to one increment. Signal data can override the amount.
  """

  use Jido.Agent,
    name: "examples_minimal_agent",
    description: "Counts increment Signals"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/basic/minimal_agent"

    route "basic.minimal.increment" do
      action %{amount: amount},
        name: "examples_minimal_agent_increment",
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end

      defaults %{amount: 1}
      define :increment, args: [{:optional, :amount}]
    end
  end
end
