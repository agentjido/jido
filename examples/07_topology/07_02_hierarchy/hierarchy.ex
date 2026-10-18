defmodule Jido.Examples.Topology.Hierarchy do
  @moduledoc "An Agent owns a team whose definition declares two workers."
  use Jido.Agent, name: "topology_hierarchy"

  routes do
    signal_source "/examples/topology/hierarchy"

    route "examples.topology.hierarchy.team.remove", as: :team_remove do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state, [Jido.Agent.Directive.agent_remove(:team)]}
      end
    end
  end

  topology do
    agent :team, Jido.Examples.Topology.Hierarchy.Team
  end
end

defmodule Jido.Examples.Topology.Hierarchy.Team do
  @moduledoc "A reusable Agent definition with its own member declarations."
  use Jido.Agent, name: "topology_team"

  topology do
    agent :workers, Jido.Examples.Topology.Cell do
      count 2
      initial_state %{label: "worker"}
    end
  end
end
