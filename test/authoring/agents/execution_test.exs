Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.ExecutionTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias JidoTest.ComposableAgent.{Team, Worker}

  test "construction binds child input but preserves the complete authored definition" do
    definition = Team.definition()
    instance = Agent.instantiate!(definition, id: "team", state: %{value: "copied", workers: 3})
    assert Agent.definition(instance) === definition
    assert {:ok, [planner, workers]} = Agent.Topology.bind(instance, instance.state)
    assert planner.state.value == "copied"
    assert workers.count == 3
    assert workers.definition === Worker.definition()
    assert instance.topology === definition.topology
    assert instance.extensions === definition.extensions
  end

  test "composition exposes data operations without the old runtime graph API" do
    assert {:module, Agent.Composition} = Code.ensure_loaded(Agent.Composition)

    for {function, arity} <- [
          project: 1,
          validate_graph: 1,
          expand_groups: 1,
          members_of: 2,
          instantiate_node: 2,
          error: 1,
          error: 2,
          static_definition: 1,
          changed_plugins: 2,
          changed_plugins: 3,
          change?: 1
        ] do
      refute function_exported?(Agent.Composition, function, arity)
    end

    instance = Team.instantiate!(id: "team", state: %{value: "copied", workers: 3})
    assert {:ok, ^instance} = Agent.Composition.bind(instance)
  end
end
