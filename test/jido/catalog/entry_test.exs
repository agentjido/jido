defmodule Jido.Catalog.EntryTest do
  use ExUnit.Case, async: true

  alias Jido.Catalog.Entry

  defmodule Target do
  end

  test "builds one complete stable definition record" do
    attrs = %{
      id: "example/send-email",
      vsn: 1,
      kind: :action,
      target: Target,
      provider: __MODULE__,
      application: :example,
      name: "Send email",
      description: "Sends one validated email"
    }

    assert {:ok, %Entry{} = entry} = Entry.new(attrs)
    assert Entry.reference(entry) == {"example/send-email", 1}
    assert Entry.new!(attrs) == entry
  end

  test "rejects incomplete, unknown, or invalid fields" do
    valid = %{
      id: "example/item",
      vsn: 1,
      kind: :flow,
      target: Target,
      provider: __MODULE__,
      application: :example
    }

    assert {:error, {:invalid_catalog_entry, :missing_fields, [:application]}} =
             valid |> Map.delete(:application) |> Entry.new()

    assert {:error, {:invalid_catalog_entry, :unknown_fields, [:extra]}} =
             valid |> Map.put(:extra, true) |> Entry.new()

    for {field, value} <- [
          {:id, "bad id"},
          {:vsn, 0},
          {:kind, nil},
          {:target, nil},
          {:provider, false},
          {:application, nil},
          {:name, <<255>>},
          {:description, :invalid}
        ] do
      assert {:error, {:invalid_catalog_entry, ^field, _reason}} =
               valid |> Map.put(field, value) |> Entry.new()
    end

    assert {:error, {:invalid_catalog_entry, :target, _reason}} =
             valid |> Map.put(:target, self()) |> Entry.new()
  end
end
