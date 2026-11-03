defmodule Jido.CatalogTest do
  use ExUnit.Case, async: true

  alias Jido.Catalog
  alias Jido.Catalog.{Entry, Error}

  defmodule ActionA do
  end

  defmodule ActionB do
  end

  defmodule Flow do
  end

  test "queries exact references, kinds, and targets" do
    action = entry("example/action", 1, :action, ActionA)
    flow = entry("example/flow", 2, :flow, Flow)
    catalog = Catalog.new!([flow, action])

    assert Catalog.list(catalog) == [action, flow]
    assert Catalog.list(catalog, :action) == [action]
    assert Catalog.get(catalog, "example/action", 1) == action
    assert Catalog.get(catalog, :action, "example/action", 1) == action
    assert Catalog.get(catalog, :flow, "example/action", 1) == nil
    assert Catalog.get_by_target(catalog, :flow, Flow) == flow
    assert Catalog.resolve(catalog, {"example/action", 1}, :action) == {:ok, ActionA}

    assert {:error, %Error{details: %{actual: :action, expected: :flow}}} =
             Catalog.resolve(catalog, {"example/action", 1}, :flow)

    assert {:error, %Error{details: %{identifier: "missing", field: "id"}}} =
             Catalog.resolve(catalog, {"missing", 1}, :action)

    assert Catalog.reference(catalog, :flow, Flow) == {:ok, {"example/flow", 2}}
  end

  test "builds an owned Catalog from a compact typed-target map" do
    catalog =
      Catalog.from_targets!(__MODULE__, :example, %{
        {"example/action", 1} => {:action, ActionA},
        {"example/flow", 2} => {:flow, Flow}
      })

    assert {:ok, ActionA} = Catalog.resolve(catalog, {"example/action", 1}, :action)
    assert {:ok, {"example/flow", 2}} = Catalog.reference(catalog, :flow, Flow)
    assert Enum.all?(Catalog.list(catalog), &(&1.provider == __MODULE__))
    assert Enum.all?(Catalog.list(catalog), &(&1.application == :example))
  end

  test "reports detailed invalid and missing references" do
    catalog = Catalog.new!([entry("example/action", 2, :action, ActionA)])

    assert {:error, %Error{details: %{field: "id", identifier: :atom}}} =
             Catalog.resolve(catalog, {:bad, 1}, :action)

    assert {:error, %Error{details: %{field: "vsn", supported_vsns: [2]}}} =
             Catalog.resolve(catalog, {"example/action", 1}, :action)

    assert {:error, %Error{details: %{kinds: []}}} = Catalog.reference(catalog, [], ActionA)
  end

  test "revision is deterministic and covers descriptive data" do
    action = entry("example/action", 1, :action, ActionA)
    flow = entry("example/flow", 1, :flow, Flow)

    first = Catalog.new!([action, flow])
    reordered = Catalog.new!([flow, action])
    renamed = Catalog.new!([%{action | name: "Renamed"}, flow])

    assert Catalog.revision(first) == Catalog.revision(reordered)
    refute Catalog.revision(first) == Catalog.revision(renamed)
    assert byte_size(Catalog.revision(first)) == 43
  end

  test "rejects duplicate references and duplicate typed targets" do
    action = entry("example/action", 1, :action, ActionA)

    duplicate_reference = %{action | target: ActionB}

    assert {:error, {:catalog_conflict, :reference, {"example/action", 1}}} =
             Catalog.new([action, duplicate_reference])

    duplicate_target = entry("example/other", 1, :action, ActionA)

    assert {:error, {:catalog_conflict, :target, {:action, ActionA}, [{"example/action", 1}, {"example/other", 1}]}} =
             Catalog.new([action, duplicate_target])
  end

  test "accepts validated Manifests and rejects other values" do
    manifest =
      Jido.Catalog.Manifest.new!(__MODULE__, :example, [
        %{id: "example/action", vsn: 1, kind: :action, target: ActionA}
      ])

    assert {:ok, catalog} = Catalog.new([manifest])
    assert [%Entry{provider: __MODULE__, application: :example}] = Catalog.list(catalog)
    assert {:error, {:invalid_catalog_value, %{id: "raw"}}} = Catalog.new([%{id: "raw"}])
    assert {:error, {:invalid_catalog, :improper_list}} = Catalog.new([manifest | :invalid])
  end

  defp entry(id, vsn, kind, target) do
    Entry.new!(%{
      id: id,
      vsn: vsn,
      kind: kind,
      target: target,
      provider: __MODULE__,
      application: :example,
      name: id
    })
  end
end
