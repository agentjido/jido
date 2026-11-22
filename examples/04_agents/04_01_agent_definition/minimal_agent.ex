defmodule Jido.Examples.MinimalAgent do
  @moduledoc """
  The smallest stateful Agent example.

  The route defaults to one increment. Signal data can override the amount.
  Start with `state: %{count: value}`. Server calls return `{:ok, agent, []}`.
  """

  alias Jido.Joi

  use Jido.Agent,
    name: "examples_minimal_agent",
    description: "Counts increment Signals"

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/basic/minimal_agent"

    route "basic.minimal.increment", as: :increment, defaults: %{amount: 1} do
      action %{amount: amount},
        schema: Joi.object(%{amount: Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end
