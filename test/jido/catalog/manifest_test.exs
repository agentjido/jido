defmodule Jido.Catalog.ManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Catalog.{Entry, Manifest}

  test "adds package ownership and sorts static entries" do
    entries = [
      %{id: "example/z", vsn: 1, kind: :flow, target: __MODULE__.Z},
      %{id: "example/a", vsn: 2, kind: :action, target: __MODULE__.A}
    ]

    assert {:ok, %Manifest{} = manifest} = Manifest.new(__MODULE__, :example, entries)
    assert Enum.map(manifest.entries, &Entry.reference/1) == [{"example/a", 2}, {"example/z", 1}]
    assert Enum.all?(manifest.entries, &(&1.provider == __MODULE__))
    assert Enum.all?(manifest.entries, &(&1.application == :example))
  end

  test "rejects improper input and conflicting entry ownership" do
    assert {:error, {:invalid_catalog_manifest, __MODULE__, :improper_list}} =
             Manifest.new(__MODULE__, :example, [%{} | :invalid])

    entry =
      Entry.new!(%{
        id: "example/item",
        vsn: 1,
        kind: :action,
        target: __MODULE__.Target,
        provider: __MODULE__.Other,
        application: :other
      })

    assert {:error, {:invalid_catalog_manifest, __MODULE__, {:entry_owner, {"example/item", 1}}}} =
             Manifest.new(__MODULE__, :example, [entry])

    assert {:error, {:invalid_catalog_manifest, nil, :provider}} =
             Manifest.new(nil, :example, [])

    assert {:error, {:invalid_catalog_manifest, __MODULE__, {:application, nil}}} =
             Manifest.new(__MODULE__, nil, [])
  end
end
