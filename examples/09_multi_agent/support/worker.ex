defmodule Jido.Examples.Worker do
  @moduledoc "A child Agent that doubles an integer and sends its parent a result Signal."

  use Jido.Agent, name: "example_worker"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/multi_agent/worker"

    route "examples.multi_agent.worker.calculate", as: :calculate do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            job_id: Jido.Joi.string() |> Jido.Joi.min(1),
            tag: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer()
          }),
        context: context do
        result = Map.put(input, :value, input.value * 2)

        reply =
          Jido.Signal.new!("examples.multi_agent.worker.result", result, source: "/examples/multi_agent/worker")

        {:ok, %{completed: context.agent_state.completed ++ [result]}, [Jido.Agent.Directive.parent_send(reply)]}
      end
    end
  end
end
