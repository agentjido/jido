defmodule Jido.Examples.Worker do
  @moduledoc "A durable worker that records one correlated calculation per Turn."

  alias Jido.Joi

  use Jido.Agent, name: "example_worker"

  state do
    schema Joi.object(%{
             completed: Joi.list(Joi.map()) |> Joi.default([])
           })
  end

  routes do
    signal_source "/examples/multi_agent/worker"

    route "examples.multi_agent.worker.calculate", as: :calculate do
      action input,
        schema:
          Joi.object(%{
            request_id: Joi.string() |> Joi.min(1),
            value: Joi.integer()
          }),
        context: context do
        result = %{request_id: input.request_id, value: input.value * 2}
        {:ok, %{completed: context.agent_state.completed ++ [result]}}
      end
    end
  end
end
