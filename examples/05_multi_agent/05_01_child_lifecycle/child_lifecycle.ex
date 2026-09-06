defmodule Jido.Examples.ChildLifecycle.Start do
  @moduledoc false
  use Jido.Action,
    name: "example_child_start",
    schema:
      Zoi.object(%{
        tag: Zoi.string() |> Zoi.min(1),
        restart: Zoi.enum([:temporary, :transient]) |> Zoi.default(:transient)
      })

  def run(input, %{agent_state: state}) do
    if input.tag in state.desired do
      {:error, Jido.Action.Error.validation_error("child tag is already in use")}
    else
      {:ok, %{state | desired: state.desired ++ [input.tag]},
       [Jido.Agent.Directive.spawn_agent(Jido.Examples.Worker, input.tag, restart: input.restart)]}
    end
  end
end

defmodule Jido.Examples.ChildLifecycle do
  @moduledoc "Starts, tracks, restarts, and stops real child Agents. PIDs stay in runtime state."
  use Jido.Agent, name: "example_child_lifecycle"

  agent do
    schema Zoi.object(%{desired: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/children"

    route "examples.children.start", Jido.Examples.ChildLifecycle.Start do
      define :start_worker, args: [:tag, {:optional, :restart}]
    end

    route "examples.children.stop" do
      action %{tag: tag},
        name: "example_child_stop",
        schema: Zoi.object(%{tag: Zoi.string() |> Zoi.min(1)}),
        context: context do
        next = %{context.agent_state | desired: List.delete(context.agent_state.desired, tag)}
        {:ok, next, [Jido.Agent.Directive.stop_child(tag)]}
      end

      define :stop_worker, args: [:tag]
    end

    route "jido.agent.child.*", Jido.Examples.KeepState
    route "examples.work.result", Jido.Examples.KeepState
  end
end
