defmodule Jido.Examples.AgentHierarchy do
  @moduledoc "Each Agent owns only its direct children. Parent shutdown stops the complete subtree."
  use Jido.Agent, name: "example_agent_hierarchy"

  agent do
    schema Zoi.object(%{
             expanded: Zoi.boolean() |> Zoi.default(false),
             depth: Zoi.integer() |> Zoi.default(0),
             lost_children: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/multi_agent/agent_hierarchy"

    route "examples.multi_agent.agent_hierarchy.grow" do
      action %{depth: depth},
        schema: Zoi.object(%{depth: Zoi.integer() |> Zoi.min(0) |> Zoi.max(4)}),
        context: context do
        state = context.agent_state

        if state.expanded do
          {:error, Jido.Action.Error.validation_error("node is already expanded")}
        else
          directives =
            if depth == 0 do
              []
            else
              Enum.flat_map(["left", "right"], fn tag ->
                [
                  Jido.Agent.Directive.spawn_child(Jido.Examples.AgentHierarchy, tag,
                    restart: :temporary
                  ),
                  Jido.Agent.Directive.emit_to_child(
                    tag,
                    Jido.Examples.AgentHierarchy.grow_signal!(depth - 1)
                  )
                ]
              end)
            end

          {:ok, %{state | expanded: true, depth: depth}, directives}
        end
      end

      define :grow, args: [:depth]
    end

    route "jido.agent.child.started", Jido.Examples.Support.KeepState

    route "jido.agent.child.exit" do
      action %{tag: tag}, context: context do
        lost = Enum.uniq(context.agent_state.lost_children ++ [tag])
        {:ok, %{context.agent_state | lost_children: lost}}
      end
    end
  end
end
