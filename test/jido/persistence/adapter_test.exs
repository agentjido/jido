defmodule JidoTest.Persistence.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence
  alias Jido.Persistence.ETS

  defmodule LegacyAdapter do
    def get(_key, _opts), do: {:error, :not_found}
    def put(_key, _value, _opts), do: :ok
    def delete(_key, _opts), do: :ok
  end

  test "normalizes module, tuple, and disabled adapter declarations" do
    assert {ETS, []} = Persistence.normalize_adapter(ETS)
    assert {ETS, [table: :custom]} = Persistence.normalize_adapter({ETS, table: :custom})
    assert Persistence.normalize_adapter(nil) == nil
    assert Persistence.normalize_adapter(false) == nil
  end

  test "validates adapter declarations" do
    assert {:ok, {ETS, []}} = Persistence.resolve_config(ETS, nil)
    assert {:ok, nil} = Persistence.resolve_config(nil, nil)

    assert {:error, {:invalid_persistence_adapter, String}} =
             Persistence.resolve_config(String, nil)
  end

  test "rejects adapters without atomic writes before use" do
    assert {:error, {:invalid_persistence_adapter, LegacyAdapter}} =
             Persistence.resolve_config(LegacyAdapter, nil)
  end
end
