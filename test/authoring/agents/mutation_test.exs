defmodule Jido.Agent.MutationAuthoringTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.Directive, as: D
  alias Jido.Test.Agent.EvolutionFixtures, as: F

  defmodule Authored do
    use Jido.Agent, name: "equivalent"

    routes do
      route "first", Jido.Test.Agent.EvolutionFixtures.Work

      route "second", Jido.Test.Agent.EvolutionFixtures.Work, defaults: %{value: 1}
    end

    topology do
      agent :worker, Jido.Test.Agent.EvolutionFixtures.Worker
    end
  end

  test "DSL, independent Map, and mutations normalize to the same definition" do
    authored = Authored.definition()

    map =
      Agent.define!(%{
        name: "equivalent",
        module: Authored,
        routes: [
          %{
            path: "first",
            handler: %{kind: :action, target: F.Work},
            state: %{source: :output, path: []}
          },
          %{
            path: "second",
            handler: %{kind: :action, target: F.Work},
            defaults: %{value: 1},
            state: %{source: :output, path: []}
          }
        ],
        topology: %{agents: [%{name: :worker, definition: F.Worker}], connections: []}
      })

    empty = Agent.define!(%{name: "equivalent", module: Authored})

    assert {:ok, mutated, _} =
             Agent.mutate(empty, [
               D.route_add("first", F.Work),
               D.route_add("second", F.Work,
                 defaults: %{value: 1},
                 state: %{source: :output, path: []}
               ),
               D.agent_add(:worker, F.Worker)
             ])

    assert authored === map
    assert mutated === map
  end

  test "mutated definitions and instances retain exact JSON round trips" do
    assert {:ok, agent, _} =
             Agent.mutate(F.agent(), [
               D.route_add("new", F.Work),
               D.agent_add(:worker, F.Worker)
             ])

    for value <- [agent, Agent.definition(agent)] do
      registry = Jido.Test.AgentServer.Registry.for(value)
      assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(value, registry)
      expected = Agent.definition(value)
      assert {:ok, ^expected} = Jido.Test.AgentServer.Registry.decode(document, registry)
      assert {:ok, json} = Jido.Test.AgentServer.Registry.encode_json(value, registry)
      assert {:ok, ^expected} = Jido.Test.AgentServer.Registry.decode_json(json, registry)
    end
  end
end
