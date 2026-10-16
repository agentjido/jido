defmodule Jido.Topology.Codec.RegistryDerivationTest do
  use JidoTest.Case, async: true

  alias Jido.Examples.Topology.{Accounts, ComposedSystem}
  alias Jido.Topology.Codec

  test "the generated Registry supports explicit encoding and decoding" do
    for definition <- [Accounts.topology(), ComposedSystem.topology()] do
      assert {:ok, document, registry} = Codec.encode(definition)
      assert {:ok, ^document} = Codec.encode(definition, registry)
      assert {:ok, ^definition} = Codec.decode(document, registry)
    end
  end

  test "generated IDs preserve first occurrence order" do
    assert {:ok, _document, %{entries: entries}} = Codec.encode(Accounts.topology())

    assert %{
             "schema/0" => {:schema, _schema},
             "agent/1" => {:agent, Jido.Examples.Topology.Cell},
             "atom/2" => {:atom, :label},
             "atom/3" => {:atom, :key_by},
             "atom/4" => {:atom, :account_id},
             "atom/5" => {:atom, :members},
             "atom/6" => {:atom, :accounts},
             "atom/7" => {:atom, :node}
           } = entries

    assert map_size(entries) == 8
  end

  test "derivation includes nested Agent, schema, and atom entries" do
    assert {:ok, _document, registry} = Codec.encode(ComposedSystem.topology())
    kinds = registry.entries |> Map.values() |> Enum.map(&elem(&1, 0))

    for kind <- [:agent, :schema, :atom] do
      assert kind in kinds
    end

    assert length(Map.values(registry.entries)) ==
             length(Enum.uniq(Map.values(registry.entries)))
  end
end
