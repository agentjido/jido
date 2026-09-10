defmodule Jido.Topology.Codec.DeriverTest do
  use JidoTest.Case, async: true

  alias Jido.Examples.Topology.{Accounts, ComposedSystem}
  alias Jido.Topology.Codec
  alias Jido.Topology.Codec.Deriver

  test "derivation preserves the Registry used by encoding" do
    for definition <- [Accounts.topology(), ComposedSystem.topology()] do
      assert {:ok, derived} = Deriver.topology(definition)
      assert {:ok, _document, encoded} = Codec.encode(definition)
      assert derived == encoded
    end
  end

  test "generated IDs preserve first occurrence order" do
    assert {:ok, %{entries: entries}} = Deriver.topology(Accounts.topology())

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
    assert {:ok, registry} = Deriver.topology(ComposedSystem.topology())
    kinds = registry.entries |> Map.values() |> Enum.map(&elem(&1, 0))

    for kind <- [:agent, :schema, :atom] do
      assert kind in kinds
    end

    assert length(Map.values(registry.entries)) ==
             length(Enum.uniq(Map.values(registry.entries)))
  end
end
