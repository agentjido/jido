defmodule Jido.CatalogTest do
  use ExUnit.Case, async: true
  alias Jido.Catalog
  alias Jido.Catalog.{Entry, Error, Manifest}

  test "resolves registered values without deciding their role" do
    values = %{{"sample/atom", 1} => :ready, {"sample/module", 2} => String, {"sample/schema", 1} => Jido.Joi.string()}
    catalog = Catalog.from_targets!(__MODULE__, :jido, values)

    for {ref, value} <- values do
      assert {:ok, ^value} = Catalog.resolve(catalog, ref)
      assert {:ok, ^ref} = Catalog.reference(catalog, value)
    end

    assert Catalog.get(catalog, "sample/module", 2).target == String
    assert Catalog.get_by_target(catalog, :ready).id == "sample/atom"
    assert Enum.map(Catalog.list(catalog), &Entry.reference/1) == Enum.sort(Map.keys(values))
    refute Map.has_key?(catalog, :kinds)
    refute Map.has_key?(catalog, :revision)
  end

  test "reports malformed, unknown, and unsupported references" do
    catalog = Catalog.from_targets!(__MODULE__, :jido, %{{"sample", 2} => :ready})
    assert {:error, %Error{details: %{field: "id"}}} = Catalog.resolve(catalog, {:bad, 1})
    assert {:error, %Error{details: %{field: "vsn", supported_vsns: [2]}}} = Catalog.resolve(catalog, {"sample", 1})
    assert {:error, %Error{details: %{identifier: "missing"}}} = Catalog.resolve(catalog, {"missing", 1})
    assert {:error, %Error{}} = Catalog.reference(catalog, :missing)
  end

  test "rejects duplicate IDs and versions with both sources" do
    first = Manifest.new!(__MODULE__, :jido, %{id: "same", target: :first})
    other = Manifest.new!(String, :stdlib, %{id: "same", target: :second})
    assert {:error, {:catalog_conflict, {"same", 1}, sources}} = Catalog.new([first, other])
    assert Enum.sort(sources) == Enum.sort([{__MODULE__, :jido}, {String, :stdlib}])
  end

  test "aliases resolve exactly and reverse lookup uses a deterministic reference" do
    catalog = Catalog.from_targets!(__MODULE__, :jido, %{{"z", 1} => :same, {"a", 1} => :same})
    assert {:ok, :same} = Catalog.resolve(catalog, {"z", 1})
    assert {:ok, {"a", 1}} = Catalog.reference(catalog, :same)
  end

  test "validates construction input without loading targets" do
    entry = Entry.new!(%{target: __MODULE__.NotLoaded, provider: __MODULE__, application: :jido})
    assert {:ok, _} = Catalog.new([entry])
    assert {:error, {:invalid_catalog_value, _}} = Catalog.new([%{}])
    assert {:error, {:invalid_catalog, :improper_list}} = Catalog.new([entry | :bad])
  end
end
