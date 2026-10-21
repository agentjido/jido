Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)

defmodule Jido.Agent.JSONTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Authoring.Registry
  alias JidoTest.ComposableAgent.{Minimal, Named, Team, PluginState}

  test "Map, struct, DSL, and instance sources produce the same definition" do
    for module <- [Minimal, Named, Team, PluginState] do
      definition = module.definition()
      instance = Agent.instantiate!(definition, id: "json-1")
      registry = JidoTest.AgentRegistry.for(definition)

      for value <- [definition, Agent.define!(Map.from_struct(definition)), instance] do
        assert {:ok, document} = JidoTest.AgentRegistry.encode(value, registry)
        assert {:ok, json} = JidoTest.AgentRegistry.encode_json(value, registry)
        assert Jason.decode!(json) == document
        assert {:ok, ^definition} = JidoTest.AgentRegistry.decode_json(json, registry)
        assert {:ok, ^definition} = JidoTest.AgentRegistry.decode(document, registry)
      end
    end
  end

  test "application Registry references are explicit and can differ from module names" do
    definition =
      Agent.define!(%{
        name: "leaf",
        schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
      })

    registry =
      Registry.new!(%{
        {"state", 1} => {:schema, definition.schema},
        {"count", 1} => {:atom, :count}
      })

    instance = Agent.instantiate!(definition, id: "leaf-1")
    assert {:ok, json} = JidoTest.AgentRegistry.encode_json(instance, registry)
    assert json =~ "\"id\":\"state\""
    assert json =~ "\"vsn\":1"
    refute json =~ "Zoi.Types"
    assert {:ok, ^definition} = JidoTest.AgentRegistry.decode_json(json, registry)
    assert {:error, _} = JidoTest.AgentRegistry.decode_json(json, %{})
    assert {:error, _} = JidoTest.AgentRegistry.encode_json(instance, %{})
  end

  test "import rejects unknown references, fields, versions, and invalid definitions" do
    instance = Agent.instantiate!(Minimal, id: "json-1")
    registry = JidoTest.AgentRegistry.for(instance)
    {:ok, document} = JidoTest.AgentRegistry.encode(instance, registry)

    invalid = [
      Map.put(document, "vsn", 99),
      Map.put(document, "unexpected", true),
      put_in(document, ["definition", "module"], %{
        "id" => "untrusted"
      }),
      put_in(document, ["definition", "module"], %{
        "id" => "untrusted",
        "vsn" => 1,
        "extra" => true
      }),
      put_in(document, ["definition", "name"], 42),
      put_in(document, ["definition", "module"], %{
        "id" => "unknown",
        "vsn" => 1
      })
    ]

    for invalid <- invalid,
        do: assert({:error, _} = JidoTest.AgentRegistry.decode(invalid, registry))

    for json <- ["not json", "[]", "null", "{}"],
        do: assert({:error, _} = JidoTest.AgentRegistry.decode_json(json, registry))
  end

  test "unknown JSON names do not create atoms" do
    registry = JidoTest.AgentRegistry.for(Minimal)
    {:ok, document} = JidoTest.AgentRegistry.encode(Minimal, registry)
    names = for n <- 1..50, do: "untrusted_agent_atom_#{System.unique_integer([:positive])}_#{n}"

    for name <- names do
      invalid =
        put_in(document, ["definition", "metadata"], %{"$type" => "atom", "id" => name})

      assert {:error, _} = JidoTest.AgentRegistry.decode_json(Jason.encode!(invalid), registry)
    end

    # Check the actual names because other tests can load modules in parallel.
    for name <- names, do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)
  end

  test "duplicate decoded keys, oversized documents, and obsolete Registry kinds are rejected" do
    registry = JidoTest.AgentRegistry.for(Minimal)
    {:ok, document} = JidoTest.AgentRegistry.encode(Minimal, registry)

    map = %{
      "$type" => "map",
      "entries" => [
        %{"key" => "same", "value" => 1},
        %{"key" => "same", "value" => 2}
      ]
    }

    assert {:error, _} =
             JidoTest.AgentRegistry.decode(
               put_in(document, ["definition", "metadata"], map),
               registry
             )

    assert {:error, _} =
             JidoTest.AgentRegistry.decode_json(String.duplicate(" ", 8_388_609), registry)

    assert {:error, _} =
             Jido.Authoring.Registry.new(%{"bad" => {:value, %URI{path: "/bad"}}})
  end
end
