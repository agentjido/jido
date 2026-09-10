defmodule Jido.Examples.ChildLifecycle do
  @moduledoc "Starts, tracks, restarts, and stops child Agents without storing PIDs."

  use Jido.Agent, name: "example_child_lifecycle"

  agent do
    schema Zoi.object(%{desired: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/multi_agent/child_lifecycle"

    route "examples.multi_agent.children.start" do
      action input,
        schema:
          Zoi.object(%{
            tag: Zoi.string() |> Zoi.min(1),
            restart: Zoi.enum([:temporary, :transient]) |> Zoi.default(:transient)
          }),
        context: context do
        if input.tag in context.agent_state.desired do
          {:error, Jido.Action.Error.validation_error("child tag is already in use")}
        else
          candidate = %{context.agent_state | desired: context.agent_state.desired ++ [input.tag]}

          directive =
            Jido.Agent.Directive.spawn_child(Jido.Examples.Worker, input.tag,
              restart: input.restart
            )

          {:ok, candidate, [directive]}
        end
      end

      define :start_worker, args: [:tag, {:optional, :restart}]
    end

    route "examples.multi_agent.children.stop" do
      action %{tag: tag},
        schema: Zoi.object(%{tag: Zoi.string() |> Zoi.min(1)}),
        context: context do
        candidate = %{
          context.agent_state
          | desired: List.delete(context.agent_state.desired, tag)
        }

        {:ok, candidate, [Jido.Agent.Directive.stop_child(tag)]}
      end

      define :stop_worker, args: [:tag]
    end

    route "jido.agent.child.*", Jido.Examples.Support.KeepState
    route "examples.multi_agent.worker.result", Jido.Examples.Support.KeepState
  end
end
