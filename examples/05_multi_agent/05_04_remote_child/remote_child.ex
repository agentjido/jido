defmodule Jido.Examples.RemoteParent do
  @moduledoc "Places an owned child on a selected Erlang node and receives its result."
  use Jido.Agent, name: "example_remote_parent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/examples/multi_agent/remote_child/parent"

    route "examples.multi_agent.remote_child.spawn", as: :request_child do
      action %{target_node: target},
        schema: Zoi.object(%{target_node: Zoi.atom()}),
        context: context do
        directive =
          Jido.Agent.Directive.spawn_child(Jido.Examples.RemoteCounter, :worker,
            node: target,
            restart: :temporary
          )

        {:ok, context.agent_state, [directive]}
      end
    end

    route "examples.multi_agent.remote_child.request_result", as: :request_result do
      action input,
        schema: Zoi.object(%{value: Zoi.integer(), request_id: Zoi.string()}),
        context: context do
        {:ok, signal} =
          Jido.Examples.RemoteCounter.calculate_signal(%{
            value: input.value,
            request_id: input.request_id
          })

        {:ok, context.agent_state, [Jido.Agent.Directive.emit_to_child(:worker, signal)]}
      end
    end

    route "examples.multi_agent.remote_child.result" do
      action result,
        schema:
          Zoi.object(%{
            value: Zoi.integer(),
            request_id: Zoi.string(),
            executed_on: Zoi.atom()
          }),
        context: context do
        {:ok, %{context.agent_state | result: result}}
      end
    end

    route "jido.agent.child.*", Jido.Examples.Support.KeepState
  end
end
