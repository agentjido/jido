defmodule Jido.Topology.DataDefinitionTest do
  use ExUnit.Case, async: true
  alias Jido.{Agent, Topology}
  alias JidoTest.AgentFixtures.CounterAgent

  test "a member keeps its authored definition and resolved state in the plan" do
    source = %{CounterAgent.definition() | name: "stored_counter", vsn: 3}
    topology = Topology.new!(name: "data", agents: [%{key: :counter, definition: source}])
    assert {:ok, instance} = Topology.instantiate(topology, id: "data")
    assert instance.definition.agents == topology.agents
    assert instance.plan.agents["agent/counter"].definition == source
    assert instance.plan.agents["agent/counter"].module == CounterAgent
    assert instance.plan.agents["agent/counter"].initial_state == %{}
    assert {:ok, document, registry} = Topology.Codec.encode(topology)
    assert {:ok, ^topology} = Topology.Codec.decode(document, registry)
  end

  test "member selectors are exclusive and require a definition rather than an instance" do
    definition = CounterAgent.definition()

    for entry <- [
          %{key: :counter},
          %{key: :counter, module: CounterAgent, definition: definition},
          %{key: :counter, definition: Agent.instantiate!(definition, id: "live")},
          %{key: :counter, module: definition},
          %{key: :counter, definition: %{definition | schema: :invalid}}
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Topology.new(name: "data", agents: [entry])
    end
  end
end
