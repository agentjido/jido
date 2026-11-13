defmodule Jido.Examples.PureCounter do
  @moduledoc "Evaluates one Agent Turn without a process or state commit."

  use Jido.Agent, name: "pure_execution_counter"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/agents/pure-counter"

    route "examples.agents.pure_counter.add", as: :add do
      action %{amount: amount},
        schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end
