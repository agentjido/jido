defmodule Jido.Agent.MutationAuthoringTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias JidoTest.AgentEvolutionFixtures, as: F

  defmodule Authored do
    use Jido.Agent, name: "equivalent"

    routes do
      route "first"
      route "second", JidoTest.AgentEvolutionFixtures.Work, defaults: %{value: 1}, emits: []
    end

    topology do
      agent :worker, JidoTest.AgentEvolutionFixtures.Worker
    end
  end

  test "DSL, independent Map, and mutations normalize to the same definition" do
    authored = Authored.definition()

    map =
      Agent.define!(%{
        name: "equivalent",
        module: Authored,
        routes: [
          %{path: "first", handler: %{kind: :pass_through}},
          %{
            path: "second",
            handler: %{kind: :action, target: F.Work},
            defaults: %{value: 1},
            emits: []
          }
        ],
        topology: %{agents: [%{name: :worker, definition: F.Worker}], connections: []}
      })

    empty = Agent.define!(%{name: "equivalent", module: Authored})

    assert {:ok, mutated, _} =
             Agent.mutate(empty, [
               D.route_add("first"),
               D.route_add("second", F.Work, defaults: %{value: 1}, emits: []),
               D.agent_add(:worker, F.Worker)
             ])

    assert authored === map
    assert mutated === map
  end

  test "mutated definitions and instances retain exact JSON round trips" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [D.route_add("new"), D.agent_add(:worker, F.Worker)])

    for value <- [agent, Agent.definition(agent)] do
      registry = JidoTest.AgentRegistry.for(value)
      assert {:ok, document} = JidoTest.AgentRegistry.encode(value, registry)
      expected = Agent.definition(value)
      assert {:ok, ^expected} = JidoTest.AgentRegistry.decode(document, registry)
      assert {:ok, json} = JidoTest.AgentRegistry.encode_json(value, registry)
      assert {:ok, ^expected} = JidoTest.AgentRegistry.decode_json(json, registry)
    end
  end
end
