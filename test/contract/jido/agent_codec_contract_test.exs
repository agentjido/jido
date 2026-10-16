defmodule JidoTest.Contract.AgentCodecTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry
  alias Jido.Error.ValidationError
  alias JidoTest.AgentContract, as: F

  defmodule CurrentPlugin do
    use Jido.Plugin

    def state_spec(_opts) do
      send(self(), :codec_plugin_read)

      case Process.get(:codec_plugin_default, 1) do
        :invalid -> :invalid
        default -> {:owned, Zoi.integer() |> Zoi.default(default)}
      end
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I20"]
  test "definitions and trusted registries accept the same Agent module forms" do
    F.with_agent("", fn generated ->
      for module <- [Agent, generated, F.BareSelection] do
        assert {:ok, %Agent{module: ^module}} = Agent.new(name: "eligible", module: module)
        assert {:ok, registry} = Registry.new(%{"agent" => {:agent, module}})
        assert {:ok, ^module} = Registry.resolve(registry, "agent", :agent)
      end

      for module <- [Enum, nil, JidoTest.MissingAgent] do
        assert {:error, %ValidationError{}} = Agent.new(name: "invalid", module: module)
        assert {:error, %ValidationError{}} = Registry.new(%{"agent" => {:agent, module}})
      end
    end)
  end

  @tag obligation: ["jido.agent.I6", "jido.agent.I8", "jido.agent.I20"]
  test "compound Codecs read each current Plugin contract once per operation" do
    definition = F.definition(plugins: [CurrentPlugin])
    assert_received :codec_plugin_read
    refute_received :codec_plugin_read

    assert {:ok, document, registry} = one_plugin_read(fn -> Codec.encode(definition) end)
    assert {:ok, ^document} = one_plugin_read(fn -> Codec.encode(definition, registry) end)
    assert {:ok, ^definition} = one_plugin_read(fn -> Codec.decode(document, registry) end)

    for default <- [3, 7] do
      Process.put(:codec_plugin_default, default)

      assert {:ok, instance} =
               one_plugin_read(fn -> Codec.decode(document, registry, id: "decoded") end)

      assert instance.state.owned === default
      assert Agent.definition(instance) === definition
    end

    Process.put(:codec_plugin_default, :invalid)

    assert {:error, %ValidationError{}} =
             one_plugin_read(fn -> Codec.decode(document, registry) end)

    assert {:error, %ValidationError{}} =
             one_plugin_read(fn -> Codec.decode(document, registry, id: "decoded") end)

    assert {:error, %ValidationError{}} =
             one_plugin_read(fn -> Codec.encode(definition, registry) end)
  end

  @tag obligation: ["jido.agent.I20", "jido.agent.I23"]
  test "nested Plugin records keep standalone validation and document error precedence" do
    definition = F.definition(plugins: [F.First, F.Second])
    assert {:ok, document, registry} = Codec.encode(definition)
    [plugin | _] = document["plugins"]
    assert {:ok, {F.First, []}} = Jido.Plugin.Codec.decode(plugin, registry)
    assert {:ok, ^plugin} = Jido.Plugin.Codec.encode(F.First, registry)

    for changes <- [
          %{"type" => "unknown"},
          %{"version" => 2},
          %{"unknown" => true},
          %{"module" => document["schema"]},
          %{"module" => "missing"},
          %{"options" => false}
        ] do
      invalid = Map.merge(plugin, changes)
      nested = %{document | "plugins" => [invalid]}
      assert {:error, %ValidationError{}} = Jido.Plugin.Codec.decode(invalid, registry)
      assert {:error, %ValidationError{} = error} = Codec.decode(nested, registry)
      assert {:error, %ValidationError{} = actual} = Codec.decode(nested, registry, unknown: true)
      assert_same_error(actual, error)
    end

    assert {:error, %ValidationError{}} = Jido.Plugin.Codec.encode(F.First, %{})
    assert {:error, %ValidationError{}} = Jido.Plugin.Codec.decode(plugin, %{})

    duplicate = %{document | "plugins" => [plugin, plugin]}

    assert {:error, %ValidationError{details: details} = error} =
             Codec.decode(duplicate, registry)

    assert details.source_path === [:plugins, 0]

    assert {:error, %ValidationError{} = actual} =
             Codec.decode(duplicate, registry, unknown: true)

    assert_same_error(actual, error)

    # A bad definition still fails before its instance options.
    invalid = %{document | "name" => nil}
    assert {:error, %ValidationError{} = error} = Codec.decode(invalid, registry)
    assert {:error, %ValidationError{} = actual} = Codec.decode(invalid, registry, unknown: true)
    assert_same_error(actual, error)
  end

  defp assert_same_error(actual, expected) do
    fields = [:__struct__, :message, :kind, :subject, :details]
    assert Map.take(actual, fields) === Map.take(expected, fields)
  end

  defp one_plugin_read(fun) do
    result = fun.()
    assert_received :codec_plugin_read
    refute_received :codec_plugin_read
    result
  end

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

  @tag obligation: ["jido.agent.I20", "jido.agent.I23"]
  test "nested map keys resolve trusted aliases before duplicate detection" do
    definition = F.definition(metadata: %{"nested" => %{key: {false, 0, 1.0}}})
    assert {:ok, document, registry} = Codec.encode(definition)
    assert {:ok, key_id} = Registry.identifier(registry, :atom, :key)

    registry = Registry.new!(Map.put(registry.entries, "old-key", {:alias, key_id}))
    key = %{"$type" => "atom", "id" => key_id}
    alias_key = %{"$type" => "atom", "id" => "old-key"}
    nested = %{"$type" => "map", "entries" => [[alias_key, 7]]}
    metadata = %{"$type" => "map", "entries" => [["nested", nested]]}

    assert {:ok, decoded} = Codec.decode(%{document | "metadata" => metadata}, registry)
    assert decoded.metadata === %{"nested" => %{key: 7}}
    assert {:ok, ^definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

    for entries <- [[["key"]], false] do
      malformed = %{nested | "entries" => entries}
      metadata = %{metadata | "entries" => [["nested", malformed]]}

      assert {:error, %ValidationError{}} =
               Codec.decode(%{document | "metadata" => metadata}, registry)
    end

    duplicate = %{nested | "entries" => [[key, 1], [alias_key, 2]]}
    metadata = %{metadata | "entries" => [["nested", duplicate]]}

    assert {:error, %ValidationError{}} =
             Codec.decode(%{document | "metadata" => metadata}, registry)

    missing_key = %{"$type" => "atom", "id" => "missing-key"}
    missing_value = %{"$type" => "atom", "id" => "missing-value"}
    nested = %{nested | "entries" => [[missing_key, missing_value]]}
    metadata = %{metadata | "entries" => [["nested", nested]]}

    assert {:error, %ValidationError{details: %{id: "missing-key", kind: :atom}}} =
             Codec.decode(%{document | "metadata" => metadata}, registry)
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
