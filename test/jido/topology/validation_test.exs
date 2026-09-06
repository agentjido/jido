defmodule Jido.Topology.ValidationTest do
  use JidoTest.Case, async: true
  alias Jido.Topology
  alias Jido.Topology.{Reference, Validation}
  alias JidoTest.AgentFixtures.CounterAgent

  test "group definitions reject conflicting or incomplete sizing options" do
    for {options, message} <- [
          {%{count: 1, members: [], key_by: :id}, "A group uses count or members, not both"},
          {%{members: [], key_by: 1}, "Group key_by must name a member field"},
          {%{members: :invalid, key_by: :id}, "Group members must be a list or input reference"},
          {%{members: []}, "A keyed group requires members and key_by"},
          {%{key_by: :id}, "A keyed group requires members and key_by"},
          {%{count: -1}, "Group count must be nonnegative or an input reference"}
        ] do
      group = Map.merge(%{key: :workers, module: CounterAgent}, options)
      assert {:error, error} = Topology.new(name: "invalid-group", groups: [group])
      assert error.message == message
    end
  end

  test "invalid topology resources and policies fail at construction" do
    for {attrs, message} <- [
          {[includes: [%{key: :child, topology: String}]],
           "Expected a topology module or definition"},
          {[includes: [%{key: :child, topology: 42}]],
           "Expected a topology module or definition"},
          {[agents: [%{key: :child, module: String}]], "Expected an Agent module"},
          {[agents: [%{key: :child, module: 42}]], "Expected an Agent module"},
          {[resources: [%{key: :bus, config: [name: :outside]}]],
           "Topology owns Bus name, Registry, and Jido scope"},
          {[connections: [%{agent: :child, to: :bus, path: ""}]],
           "Bus subscription path must be a nonempty string"},
          {[connections: [%{agent: :child, to: :bus, path: "a..b"}]],
           "Invalid Bus subscription path"},
          {[startup: %{concurrency: 0}], "Expected a positive integer"},
          {[startup: %{ready: :none}], "Unsupported topology option"}
        ] do
      assert {:error, error} = Topology.new([name: "invalid-topology"] ++ attrs)
      assert error.message == message
    end
  end

  test "topology input must be a map and can supply the full initial Agent state" do
    for input <- [[], ~D[2026-01-01], nil] do
      assert {:error, error} = Validation.parse_input(Zoi.any(), input)
      assert error.message == "Topology input must be a plain map"
    end

    schema = Zoi.any() |> Zoi.transform(fn _ -> 42 end)
    assert {:error, error} = Validation.parse_input(schema, %{})
    assert error.message == "Topology input schema must produce a map"

    definition =
      Topology.new!(
        name: "state-reference",
        schema: Zoi.object(%{initial: Zoi.map()}),
        agents: [%{key: :counter, module: CounterAgent, initial_state: Reference.input(:initial)}]
      )

    assert {:ok, instance} =
             Topology.instantiate(definition,
               id: "input-state",
               input: %{initial: %{count: 4, history: []}}
             )

    assert instance.input.initial.count == 4
    assert instance.plan.agents["agent/counter"].initial_state == %{count: 4, history: []}
  end
end
