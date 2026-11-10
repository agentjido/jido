Code.require_file("support/jido_agent/composable_fixtures.exs", __DIR__)
Code.require_file("support/jido_flow/boundaries.ex", __DIR__)

defmodule Jido.Authoring.SafetyTest do
  use ExUnit.Case, async: true
  @moduletag :authoring

  alias Jido.Agent
  alias Jido.Flow.Ref
  alias Jido.Test.Agent.Authoring.Minimal
  alias Jido.Test.Flow.Authoring.Boundaries
  alias Jido.Test.Flow.Codec

  test "DSL, Map, and JSON authoring do not execute Action work" do
    expected = Boundaries.Inert.flow()

    data = %{
      name: Boundaries.Inert.name(),
      components: [
        %{
          kind: :step,
          name: "bomb",
          action: Boundaries.Bomb,
          params: %{value: Ref.input(:value)}
        }
      ],
      output: %{value: Ref.result("bomb", :value)}
    }

    assert {:ok, from_map} = Jido.Test.Flow.Builder.new(data)
    assert from_map === expected
    assert {:ok, document, catalog} = Codec.encode(expected)
    assert {:ok, ^expected} = Codec.decode(document, catalog)

    definition = Agent.define!(%{name: "inert_agent"})
    agent_catalog = Jido.Test.AgentServer.Registry.for(definition)
    assert {:ok, agent_document} = Jido.Test.AgentServer.Registry.encode(definition, agent_catalog)
    assert {:ok, ^definition} = Jido.Test.AgentServer.Registry.decode(agent_document, agent_catalog)
  end

  test "unknown JSON names do not create atoms" do
    catalog = Jido.Test.AgentServer.Registry.for(Minimal)
    assert {:ok, document} = Jido.Test.AgentServer.Registry.encode(Minimal, catalog)
    name = "untrusted_authoring_atom_#{System.unique_integer([:positive])}"

    invalid =
      put_in(document, ["definition", "metadata"], %{
        "$type" => "atom",
        "id" => name
      })

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    assert {:error, _} = Jido.Test.AgentServer.Registry.decode_json(Jason.encode!(invalid), catalog)
    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
  end

  test "stored definitions require their Catalog and enforce the JSON size limit" do
    catalog = Jido.Test.AgentServer.Registry.for(Minimal)
    assert {:ok, json} = Jido.Test.AgentServer.Registry.encode_json(Minimal, catalog)
    assert_raise ArgumentError, fn -> Jido.Test.AgentServer.Registry.decode_json(json, %{}) end

    assert {:error, _} =
             Jido.Test.AgentServer.Registry.decode_json(String.duplicate(" ", 8_388_609), catalog)
  end
end
