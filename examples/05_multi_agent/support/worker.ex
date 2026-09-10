defmodule Jido.Examples.Worker do
  @moduledoc "A child Agent that doubles an integer and sends its parent a result Signal."

  use Jido.Agent, name: "example_worker"

  agent do
    schema Zoi.object(%{completed: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/multi_agent/worker"

    route "examples.multi_agent.worker.calculate" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string() |> Zoi.min(1),
            job_id: Zoi.string() |> Zoi.min(1),
            tag: Zoi.string() |> Zoi.min(1),
            value: Zoi.integer()
          }),
        context: context do
        result = Map.put(input, :value, input.value * 2)

        reply =
          Jido.Signal.new!("examples.multi_agent.worker.result", result,
            source: "/examples/multi_agent/worker"
          )

        {:ok, %{completed: context.agent_state.completed ++ [result]},
         [Jido.Agent.Directive.emit_to_parent(reply)]}
      end

      define :calculate, args: [:request_id, :job_id, :tag, :value]
    end
  end
end
