defmodule Jido.Examples.AgentHierarchy.Grow do
  @moduledoc false
  use Jido.Action,
    name: "example_hierarchy_grow",
    schema: Zoi.object(%{depth: Zoi.integer() |> Zoi.min(0) |> Zoi.max(4)})

  alias Jido.Agent.Directive
  alias Jido.Examples.AgentHierarchy

  def run(%{depth: depth}, %{agent_state: %{expanded: false} = state}) do
    directives =
      if depth == 0 do
        []
      else
        Enum.flat_map(["left", "right"], fn tag ->
          [
            Directive.spawn_agent(AgentHierarchy, tag, restart: :temporary),
            Directive.emit_to_child(tag, AgentHierarchy.grow_signal!(depth - 1))
          ]
        end)
      end

    {:ok, %{state | expanded: true, depth: depth}, directives}
  end

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("node is already expanded")}
end

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
    signal_source "/examples/hierarchy"

    route "examples.hierarchy.grow", Jido.Examples.AgentHierarchy.Grow do
      define :grow, args: [:depth]
    end

    route "jido.agent.child.started", Jido.Examples.KeepState

    route "jido.agent.child.exit" do
      action %{tag: tag}, name: "example_hierarchy_exit", context: context do
        lost = Enum.uniq(context.agent_state.lost_children ++ [tag])
        {:ok, %{context.agent_state | lost_children: lost}}
      end
    end
  end
end
