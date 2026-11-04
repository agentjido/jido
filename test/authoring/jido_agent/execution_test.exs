Code.require_file("../support/jido_agent/composable_fixtures.exs", __DIR__)

defmodule Jido.Agent.Authoring.ExecutionTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Test.Agent.Authoring.{Team, Worker}

  test "construction binds child input but preserves the complete authored definition" do
    definition = Team.definition()
    instance = Agent.instantiate!(definition, id: "team", state: %{value: "copied", workers: 3})
    assert Agent.definition(instance) === definition

    assert {:ok, [planner, workers]} =
             Agent.Topology.bind(instance, instance.state, &Agent.Validation.resolve/2)

    assert planner.state.value == "copied"
    assert workers.count == 3
    assert workers.definition === Worker.definition()
    assert instance.topology === definition.topology
    assert instance.plugins === definition.plugins
  end

  test "Mutation owns state composition without the old runtime graph API" do
    assert {:module, Agent.Mutation} = Code.ensure_loaded(Agent.Mutation)

    for {function, arity} <- [
          project: 1,
          validate_graph: 1,
          expand_groups: 1,
          members_of: 2,
          instantiate_node: 2,
          error: 1,
          error: 2,
          static_definition: 1,
          change?: 1
        ] do
      refute function_exported?(Agent.Mutation, function, arity)
    end

    instance = Team.instantiate!(id: "team", state: %{value: "copied", workers: 3})
    assert {:ok, ^instance} = Agent.Mutation.bind(instance)
  end
end
