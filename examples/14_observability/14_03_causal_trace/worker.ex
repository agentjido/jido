defmodule Jido.Examples.CausalTrace.Worker do
  @moduledoc "A temporary child Agent that reports one computed value to its parent."

  use Jido.Agent, name: "example_causal_worker"

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/runtime/causal_trace"

    route "examples.runtime.causal_trace.compute", as: :compute do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string(),
            slot: Jido.Joi.enum([:left, :right]),
            value: Jido.Joi.integer()
          }),
        context: context do
        value = input.value * 2

        {:ok, result} =
          Jido.Examples.CausalTrace.collect_result_signal(%{
            request_id: input.request_id,
            slot: input.slot,
            value: value
          })

        {:ok, %{context.agent_state | value: value}, [Jido.Agent.Directive.parent_send(result)]}
      end
    end
  end
end
