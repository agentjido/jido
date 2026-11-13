Code.require_file("package_catalog.ex", __DIR__)

defmodule Jido.Examples.PackageCatalogTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Catalog
  alias Jido.Catalog.Discovery
  alias Jido.Examples.PackageCatalog
  alias Jido.Examples.PackageCatalog.NormalizeName

  setup do
    on_exit(fn -> :ok = Discovery.refresh() end)
  end

  test "discovery publishes Action and package vocabulary contributions together" do
    assert :ok = PackageCatalog.refresh()
    assert Discovery.ready?()

    assert %{target: NormalizeName, provider: NormalizeName, application: :jido} =
             PackageCatalog.resolve_action()

    assert %{target: :display_name} = PackageCatalog.resolve_value()

    assert {:ok, NormalizeName} =
             Catalog.resolve(Discovery.catalog(), {"examples/catalog/normalize-name", 1})
  end

  test "a failed refresh keeps the last complete publication" do
    assert :ok = PackageCatalog.refresh()
    before = Discovery.catalog()

    assert {:error, {:module_not_loaded, :nofile}} =
             Discovery.refresh(
               applications: [],
               modules: [{Jido.Examples.PackageCatalog.NotInstalled, :jido}]
             )

    assert Discovery.catalog() == before
  end
end
