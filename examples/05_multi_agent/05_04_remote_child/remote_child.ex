defmodule Jido.Examples.RemoteParent do
  @moduledoc "Places an owned child on a selected Erlang node and receives its result."
  use Jido.Agent, name: "example_remote_parent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/examples/multi_agent/remote_child/parent"

    route "examples.multi_agent.remote_child.spawn" do
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

      define :request_child, args: [:target_node]
    end

    route "examples.multi_agent.remote_child.request_result" do
      action input,
        schema: Zoi.object(%{value: Zoi.integer(), request_id: Zoi.string()}),
        context: context do
        signal = Jido.Examples.RemoteCounter.calculate_signal!(input.value, input.request_id)
        {:ok, context.agent_state, [Jido.Agent.Directive.emit_to_child(:worker, signal)]}
      end

      define :request_result, args: [:value, :request_id]
    end

    route "examples.multi_agent.remote_child.result" do
      action result, context: context do
        {:ok, %{context.agent_state | result: result}}
      end
    end

    route "jido.agent.child.*", Jido.Examples.Support.KeepState
  end
end
