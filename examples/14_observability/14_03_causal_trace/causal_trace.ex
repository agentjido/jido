defmodule Jido.Examples.CausalTrace do
  @moduledoc "Shows one causal trace across a routed Agent Turn."
  use Jido.Agent, name: "example_causal_trace"

  state do
    schema Jido.Joi.object(%{results: Jido.Joi.map() |> Jido.Joi.default(%{})})
  end

  routes do
    signal_source "/examples/runtime/causal_trace"

    route "examples.runtime.causal_trace.compute", as: :compute do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | results: %{left: value * 2, right: value * 2}}}
      end
    end
  end
end
