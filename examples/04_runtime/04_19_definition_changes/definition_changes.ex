defmodule Jido.Examples.DefinitionChanges do
  @moduledoc "Adds an exact route ahead of a wildcard through one validated mutation batch."
  use Jido.Agent, name: "runtime_definition_changes"
  alias Jido.Agent.Directive, as: D

  agent do
    schema Zoi.object(%{selected: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/runtime/definition_changes"

    route "examples.runtime.definition.install", as: :install do
      action _input, context: context do
        {:ok, context.agent_state,
         [
           D.route_add(
             "examples.runtime.definition.work.exact",
             Jido.Examples.DefinitionChanges.Exact
           ),
           D.routes_reorder([
             "examples.runtime.definition.install",
             "examples.runtime.definition.remove",
             "examples.runtime.definition.work.exact",
             "examples.runtime.definition.work.*"
           ])
         ]}
      end
    end

    route "examples.runtime.definition.remove", as: :remove do
      action _input, context: context do
        {:ok, context.agent_state, [D.route_remove("examples.runtime.definition.work.exact")]}
      end
    end

    route "examples.runtime.definition.work.*" do
      action _input, context: context do
        {:ok, %{context.agent_state | selected: "wildcard"}}
      end
    end
  end
end

defmodule Jido.Examples.DefinitionChanges.Exact do
  @moduledoc "A named Action gives the dynamically installed route a stable code reference."
  use Jido.Action, name: "runtime_definition_exact"
  def run(_, context), do: {:ok, %{context.agent_state | selected: "exact"}}
end
