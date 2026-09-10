defmodule Jido.Examples.Handoff.Worker do
  @moduledoc "Accepts one ownership generation and reports results to its parent."
  use Jido.Agent, name: "research_handoff_worker"

  alias Jido.Agent.Directive
  alias Jido.Examples.Handoff

  agent do
    schema Zoi.object(%{
             request: Zoi.string() |> Zoi.default(""),
             owner: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/research/handoff/worker"

    route "examples.research.handoff.worker.prepare" do
      action input,
        schema:
          Zoi.object(%{
            request: Zoi.string(),
            owner: Zoi.string(),
            generation: Zoi.integer()
          }),
        context: _context do
        {:ok, input}
      end
    end

    route "examples.research.handoff.worker.ack" do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state,
         [
           Directive.emit_to_parent(
             Handoff.signal("examples.research.handoff.ack", context.agent_state)
           )
         ]}
      end

      define :acknowledge
    end

    route "examples.research.handoff.worker.complete" do
      action %{result: result},
        schema: Zoi.object(%{result: Zoi.string()}),
        context: context do
        data = Map.put(context.agent_state, :result, result)

        {:ok, context.agent_state,
         [Directive.emit_to_parent(Handoff.signal("examples.research.handoff.result", data))]}
      end

      define :complete, args: [:result]
    end
  end
end
