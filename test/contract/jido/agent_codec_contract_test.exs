defmodule JidoTest.Contract.AgentCodecTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry
  alias Jido.Error.ValidationError
  alias JidoTest.AgentContract, as: F

  @tag obligation: ["jido.agent.I20", "jido.agent.I5"]
  test "version-2 documents round trip exact static data and omit live values" do
    definition =
      F.definition(
        vsn: 7,
        description: "portable",
        plugins: [{F.First, [initial: 2]}, F.Second],
        metadata: %{date: ~D[2026-10-15], exact: [1, 1.0, :atom, {:tag, <<255>>}]},
        routes: [
          {"test.run", {F.Return, %{amount: 2}}, priority: 8},
          {"test.flow", F.Flow, priority: -3}
        ]
      )

    instance = Agent.instantiate!(definition, id: "live-id", state: %{count: 4})
    assert {:ok, document, registry} = Codec.encode(definition)

    assert Map.keys(document) |> Enum.sort() ==
             Enum.sort(
               ~w(type version module vsn name description schema metadata plugins routes)
             )

    assert document["type"] == "jido.agent"
    assert document["version"] === 2
    assert document["name"] == "contract"
    assert document["vsn"] == 7
    assert document["description"] == "portable"
    assert Enum.map(document["routes"], & &1["priority"]) == [8, -3]
    assert Enum.map(document["routes"], & &1["kind"]) == ["action", "flow"]
    assert {:ok, ^document} = Codec.encode(instance, registry)
    # Encoding extracts static data; it does not parse live state.
    assert {:ok, ^document} = Codec.encode(%{instance | state: %{invalid: self()}}, registry)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

    assert {:ok, ^instance} =
             Codec.decode(document, registry, id: instance.id, state: instance.state)

    assert {:error, %ValidationError{}} = Codec.encode(%{definition | id: "half"})
    assert {:error, %ValidationError{}} = Codec.encode(nil)
  end

  @tag obligation: "jido.agent.I20"
  test "stable trusted Registry references supply code and schemas" do
    definition = Agent.new!(name: "minimal", schema: Zoi.object(%{}))

    registry =
      Registry.new!(%{"agent" => {:agent, Agent}, "schema" => {:schema, definition.schema}})

    expected = %{
      "type" => "jido.agent",
      "version" => 2,
      "module" => "agent",
      "vsn" => nil,
      "name" => "minimal",
      "description" => nil,
      "schema" => "schema",
      "metadata" => %{"$type" => "map", "entries" => []},
      "plugins" => [],
      "routes" => []
    }

    assert {:ok, ^expected} = Codec.encode(definition, registry)
    assert {:ok, ^definition} = Codec.decode(expected, registry)

    for changes <- [
          %{"version" => 1},
          %{"type" => "other"},
          %{"id" => "live"},
          %{"state" => %{}},
          %{"module" => "Elixir.Untrusted#{System.unique_integer([:positive])}"},
          %{"schema" => "agent"},
          %{"plugins" => %{}},
          %{"routes" => %{}},
          %{"unknown" => 1}
        ] do
      assert {:error, %ValidationError{}} = Codec.decode(Map.merge(expected, changes), registry)
    end

    for field <- Map.keys(expected),
        do:
          assert(
            {:error, %ValidationError{}} = Codec.decode(Map.delete(expected, field), registry)
          )

    assert {:error, %ValidationError{}} = Codec.decode(expected, %{})
  end

  @tag obligation: "jido.agent.I20"
  test "route documents reject untrusted kinds, malformed defaults and local match closures" do
    definition = F.definition(metadata: %{uri: %URI{port: 1}})
    {:ok, document, registry} = Codec.encode(definition)
    [route] = document["routes"]

    for changes <- [
          %{"kind" => "unknown"},
          %{"target" => "missing"},
          %{"match" => "missing"},
          %{"priority" => "high"},
          %{"defaults" => false},
          %{"extra" => 1}
        ] do
      assert {:error, %{__exception__: true}} =
               Codec.decode(%{document | "routes" => [Map.merge(route, changes)]}, registry)
    end

    closure = F.definition(routes: [{"test.run", F.Return, match: fn _ -> true end}])
    assert {:error, %ValidationError{}} = Codec.encode(closure)

    for target <- [F.Return, {F.Return, %{}}, {F.Return, %{flag: false}}] do
      value = F.definition(routes: [{"test.run", target}])
      assert {:ok, encoded, references} = Codec.encode(value)
      assert {:ok, ^value} = Codec.decode(encoded, references)
    end
  end

  @tag obligation: "jido.agent.I20"
  test "document limits reject excess depth, string size, and collection size" do
    {:ok, document, registry} = Codec.encode(F.definition())
    nested = Enum.reduce(1..102, nil, fn _, acc -> [acc] end)

    for extra <- [nested, String.duplicate("a", 1_048_577), List.duplicate(nil, 10_001)] do
      assert {:error, %ValidationError{}} =
               Codec.decode(Map.put(document, "metadata", extra), registry)
    end

    assert {:error, %ValidationError{}} = Codec.decode(nil, registry)
  end

  @tag obligation: "jido.agent.I20"
  test "external route predicates use trusted references and retain their exact function" do
    definition = F.definition(routes: [{"test.run", F.Return, match: &F.match?/1}])
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert {:ok, ^document} = Codec.encode(definition, registry)
    assert {:error, %ValidationError{}} = Codec.encode(definition, %{})
    instance = Agent.instantiate!(definition, id: "a")
    assert {:ok, ^document} = Codec.encode(%{instance | state: %{unparsed: self()}}, registry)
    assert {:error, %ValidationError{}} = Codec.encode(%{instance | id: ""}, registry)
  end

  @tag obligation: ["jido.agent.I20", "jido.agent.I23"]
  test "malformed documents produce nonempty validation messages" do
    {:ok, document, registry} = Codec.encode(F.definition())
    [route] = document["routes"]

    for invalid <- [
          nil,
          %{document | "version" => 1},
          %{document | "routes" => %{}},
          %{document | "routes" => [Map.put(route, "kind", "unknown")]}
        ] do
      assert {:error, %ValidationError{message: message}} = Codec.decode(invalid, registry)
      assert is_binary(message) and byte_size(message) > 0
    end
  end
end
