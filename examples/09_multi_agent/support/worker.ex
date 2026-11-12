defmodule Jido.Examples.Worker do
  @moduledoc "A durable worker that records one correlated calculation per Turn."

  use Jido.Agent, name: "example_worker"

  state do
    schema Jido.Joi.object(%{
             completed: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([])
           })
  end

  routes do
    signal_source "/examples/multi_agent/worker"

    route "examples.multi_agent.worker.calculate", as: :calculate do
      action input,
        schema:
          Jido.Joi.object(%{
            request_id: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer()
          }),
        context: context do
        result = %{request_id: input.request_id, value: input.value * 2}
        {:ok, %{completed: context.agent_state.completed ++ [result]}}
      end
    end
  end
end
