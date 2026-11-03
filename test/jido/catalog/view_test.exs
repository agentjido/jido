defmodule Jido.Catalog.ViewTest do
  use ExUnit.Case, async: true

  alias Jido.Catalog
  alias Jido.Catalog.{Entry, View}

  test "filters visible kinds and targets without changing the Catalog" do
    action_a = entry("example/a", :action, __MODULE__.ActionA)
    action_b = entry("example/b", :action, __MODULE__.ActionB)
    flow = entry("example/flow", :flow, __MODULE__.Flow)
    catalog = Catalog.new!([flow, action_b, action_a])

    view = View.new!(catalog, kinds: [:action], targets: [__MODULE__.ActionB])

    assert View.list(view) == [action_b]
    assert View.list(view, :action) == [action_b]
    assert View.get(view, "example/a", 1) == nil
    assert View.get(view, "example/b", 1) == action_b
    assert View.get_by_target(view, :flow, __MODULE__.Flow) == nil
    assert View.allows?(view, action_b)
    refute View.allows?(view, action_a)
    assert View.revision(view) == Catalog.revision(catalog)
    assert Catalog.list(catalog) == [action_a, action_b, flow]
  end

  test "an unrestricted View exposes all inventory but grants no authority" do
    entry = entry("example/a", :action, __MODULE__.ActionA)
    catalog = Catalog.new!([entry])
    view = View.new!(catalog)

    assert View.list(view) == [entry]
    refute function_exported?(View, :authorize, 2)
    refute function_exported?(View, :execute, 2)
  end

  test "rejects malformed filters and options" do
    catalog = Catalog.new!([])

    assert {:error, {:invalid_catalog_view, :kinds}} = View.new(catalog, kinds: :action)
    assert {:error, {:invalid_catalog_view, :targets}} = View.new(catalog, targets: :all_actions)
    assert {:error, {:invalid_catalog_view, :options}} = View.new(catalog, authorize: true)
    assert {:error, {:invalid_catalog_view, :catalog}} = View.new(:invalid)
  end

  defp entry(id, kind, target) do
    Entry.new!(%{
      id: id,
      vsn: 1,
      kind: kind,
      target: target,
      provider: __MODULE__,
      application: :example
    })
  end
end
