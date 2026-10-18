defmodule JidoTest.Authoring.Agents.DurableTest do
  use ExUnit.Case, async: true
  @moduletag :authoring

  alias Jido.Agent
  alias JidoTest.DurableFixtures, as: F

  defmodule Authored do
    use Jido.Agent, name: "authored_durable"

    routes do
      route "request", F.Flow
    end
  end

  test "durable Flow routes need no Plugin or extra Agent state" do
    definition =
      Agent.define!(%{
        module: Authored,
        name: "authored_durable",
        routes: [
          %{path: "request", handler: %{kind: :flow, target: F.Flow}}
        ]
      })

    assert Authored.definition() === definition
    agent = Agent.instantiate!(definition, id: "durable-one")
    assert agent.state == %{}
    assert {:ok, snapshot} = Jido.Persistence.snapshot(agent)
    assert {:ok, ^agent} = Jido.Persistence.restore(snapshot)
  end

  test "saved member slot identities survive Agent JSON encoding" do
    definition =
      Agent.define!(%{
        name: "saved_slots",
        topology: %{
          agents: [
            %{
              name: :workers,
              definition: F.Worker,
              count: 2,
              identities: %{1 => "one", 2 => "two"}
            }
          ],
          connections: []
        }
      })

    assert {:ok, _document, registry} = Agent.Codec.encode(definition)
    assert {:ok, json} = Agent.to_json(definition, registry)
    assert {:ok, ^definition} = Agent.from_json(json, registry)
  end
end
