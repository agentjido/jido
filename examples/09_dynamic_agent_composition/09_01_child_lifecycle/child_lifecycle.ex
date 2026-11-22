defmodule Jido.Examples.ChildLifecycle do
  @moduledoc "A durable worker whose logical identity is separate from its activation."

  alias Jido.Joi

  use Jido.Agent, name: "example_child_lifecycle"

  state do
    schema Joi.object(%{count: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/multi_agent/child_lifecycle"

    route "examples.multi_agent.children.increment", as: :increment do
      action _input, context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end
