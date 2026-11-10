defmodule Jido.Catalog.EntryTest do
  use ExUnit.Case, async: true
  alias Jido.Catalog.Entry

  test "defaults identity for modules, atoms, and named schemas" do
    base = %{provider: __MODULE__, application: :jido}
    module = Entry.new!(Map.put(base, :target, String))
    atom = Entry.new!(Map.put(base, :target, :ready))
    schema = Entry.new!(Map.merge(base, %{name: :input, target: Jido.Joi.string()}))
    assert module.id == "Elixir.String"
    assert atom.id == "#{__MODULE__}/ready"
    assert schema.id == "#{__MODULE__}/input"
    assert Enum.all?([module, atom, schema], &(&1.vsn == 1))
    assert Entry.new!(Map.merge(base, %{target: String, id: "stable", vsn: 3})).id == "stable"
  end

  test "validates identity and ownership but accepts explicitly registered values" do
    valid = %{target: :anything, provider: __MODULE__, application: :jido}

    for {key, value} <- [id: "bad id", vsn: 0, provider: false, provider: %{}, application: nil] do
      assert {:error, {:invalid_catalog_entry, ^key, _}} = Entry.new(Map.put(valid, key, value))
    end

    assert {:error, {:invalid_catalog_entry, :unknown_fields, [:kind]}} = Entry.new(Map.put(valid, :kind, :action))
    assert {:ok, _} = Entry.new(Map.put(valid, :target, self()) |> Map.put(:id, "explicit"))
    refute function_exported?(Entry, :kind, 1)
  end
end
