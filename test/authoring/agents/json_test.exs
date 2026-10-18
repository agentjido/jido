Code.require_file("../support/agents/composable_fixtures.exs", __DIR__)

defmodule Jido.Agent.JSONTest do
  use ExUnit.Case, async: true
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry
  alias JidoTest.ComposableAgent.{Minimal, Named, Team, PluginState}

  test "Map, struct and DSL definitions and complete instances round trip exactly" do
    for module <- [Minimal, Named, Team, PluginState] do
      definition = module.definition()
      instance = Agent.instantiate!(definition, id: "json-1")

      for value <- [definition, Agent.define!(Map.from_struct(definition)), instance] do
        assert {:ok, document, registry} = Codec.encode(value)
        assert {:ok, json} = Agent.to_json(value, registry)
        assert Jason.decode!(json) == document
        assert {:ok, ^value} = Agent.from_json(json, registry)
        assert {:ok, ^value} = Codec.decode(document, registry)
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
      Registry.new!(%{"state/v1" => {:schema, definition.schema}, "count" => {:atom, :count}})

    instance = Agent.instantiate!(definition, id: "leaf-1")
    assert {:ok, json} = Agent.to_json(instance, registry)
    assert json =~ "state/v1"
    refute json =~ "Zoi.Types"
    assert {:ok, ^instance} = Agent.from_json(json, registry)
    assert {:error, _} = Agent.from_json(json, %{})
    assert {:error, _} = Agent.to_json(instance, %{})
  end

  test "import rejects unknown symbols, references, fields, versions and invalid state" do
    instance = Agent.instantiate!(Minimal, id: "json-1")
    {:ok, document, registry} = Codec.encode(instance)

    invalid = [
      Map.put(document, "version", 99),
      Map.put(document, "unexpected", true),
      put_in(document, ["agent", "module"], %{
        "$type" => "reference",
        "kind" => "agent",
        "id" => "untrusted"
      }),
      put_in(document, ["agent", "module"], %{
        "$type" => "reference",
        "kind" => "source_code",
        "id" => "untrusted"
      }),
      put_in(document, ["agent", "name"], %{
        "$type" => "symbol",
        "name" => "unknown_do_not_create_atom"
      }),
      put_in(document, ["agent", "id"], ""),
      put_in(document, ["agent", "state"], nil),
      put_in(document, ["agent", "module"], %{
        "$type" => "reference",
        "kind" => "schema",
        "id" => "unknown"
      })
    ]

    for invalid <- invalid, do: assert({:error, _} = Codec.decode(invalid, registry))

    for json <- ["not json", "[]", "null", "{}"],
        do: assert({:error, _} = Agent.from_json(json, registry))
  end

  test "unknown JSON names do not create atoms" do
    {:ok, document, registry} = Codec.encode(Minimal)
    names = for n <- 1..50, do: "untrusted_agent_atom_#{System.unique_integer([:positive])}_#{n}"

    for name <- names do
      invalid = put_in(document, ["agent", "name"], %{"$type" => "symbol", "name" => name})
      assert {:error, _} = Agent.from_json(Jason.encode!(invalid), registry)
    end

    # Check the actual names because other tests can load modules in parallel.
    for name <- names, do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)
  end

  test "duplicate decoded keys, oversized documents and live registry values are rejected" do
    {:ok, document, registry} = Codec.encode(Minimal)
    map = %{"$type" => "map", "entries" => [["same", 1], ["same", 2]]}
    assert {:error, _} = Codec.decode(put_in(document, ["agent", "metadata"], map), registry)
    assert {:error, _} = Agent.from_json(String.duplicate(" ", 8_388_609), registry)

    assert {:error, _} =
             Registry.new(%{
               "bad" => {:value, %URI{path: inspect(self())}},
               "live" => {:atom, self()}
             })
  end
end
