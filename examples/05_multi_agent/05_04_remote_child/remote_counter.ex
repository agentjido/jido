defmodule Jido.Examples.RemoteCounter do
  @moduledoc "A child Agent that runs on its owning parent's selected Erlang node."
  use Jido.Agent, name: "example_remote_counter"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/multi_agent/remote_child/counter"

    route "examples.multi_agent.remote_child.record", as: :record do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end
    end

    route "examples.multi_agent.remote_child.calculate", as: :calculate do
      action input,
        schema: Zoi.object(%{value: Zoi.integer(), request_id: Zoi.string()}),
        context: context do
        result = Map.put(input, :executed_on, node())

        reply =
          Jido.Signal.new!("examples.multi_agent.remote_child.result", result,
            source: "/examples/multi_agent/remote_child/counter"
          )

        {:ok, %{context.agent_state | value: input.value},
         [Jido.Agent.Directive.emit_to_parent(reply)]}
      end
    end
  end
end
