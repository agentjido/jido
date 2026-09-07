defmodule JidoTest.Persistence.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence
  alias Jido.Persistence.ETS

  defmodule LegacyAdapter do
    def get(_key, _opts), do: {:error, :not_found}
    def put(_key, _value, _opts), do: :ok
    def delete(_key, _opts), do: :ok
  end

  defmodule CompatibleAdapter do
    def get(_key, _opts), do: {:error, :not_found}
    def put(_key, _value, _opts), do: :ok
    def compare_and_swap(_key, _expected, _value, _opts), do: :ok
    def delete(_key, _opts), do: :ok
  end

  defmodule RejectingAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def validate_options(_opts), do: {:error, :rejected}

    @impl true
    def get(_key, _opts), do: {:error, :not_found}
    @impl true
    def put(_key, _value, _opts), do: :ok
    @impl true
    def compare_and_swap(_key, _expected, _value, _opts), do: :ok
    @impl true
    def delete(_key, _opts), do: :ok
  end

  defmodule FaultyValidatorAdapter do
    @behaviour Jido.Persistence.Adapter

    @impl true
    def validate_options(opts) do
      case Keyword.fetch!(opts, :failure) do
        :invalid_result -> :invalid_result
        :raise -> raise "validator failed"
        :throw -> throw(:validator_failed)
        :exit -> exit(:validator_failed)
      end
    end

    @impl true
    def get(_key, _opts), do: {:error, :not_found}
    @impl true
    def put(_key, _value, _opts), do: :ok
    @impl true
    def compare_and_swap(_key, _expected, _value, _opts), do: :ok
    @impl true
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

  test "requires keyword options and supports optional adapter validation" do
    assert {:ok, {CompatibleAdapter, []}} = Persistence.resolve_config(CompatibleAdapter, nil)

    assert {:error, {:invalid_persistence_config, _}} =
             Persistence.resolve_config({ETS, [:not_keyword]}, nil)

    assert {:error, {:invalid_persistence_options, RejectingAdapter, :rejected}} =
             Persistence.resolve_config(RejectingAdapter, nil)

    assert {:error, {:invalid_persistence_options, ETS, _reason}} =
             Persistence.resolve_config({ETS, table: "not-an-atom"}, nil)
  end

  test "contains all adapter validator failure modes" do
    assert {:error,
            {:invalid_persistence_options, FaultyValidatorAdapter,
             {:invalid_result, :invalid_result}}} =
             Persistence.resolve_config({FaultyValidatorAdapter, failure: :invalid_result}, nil)

    assert {:error,
            {:invalid_persistence_options, FaultyValidatorAdapter,
             {:error, %RuntimeError{message: "validator failed"}}}} =
             Persistence.resolve_config({FaultyValidatorAdapter, failure: :raise}, nil)

    assert {:error,
            {:invalid_persistence_options, FaultyValidatorAdapter, {:throw, :validator_failed}}} =
             Persistence.resolve_config({FaultyValidatorAdapter, failure: :throw}, nil)

    assert {:error,
            {:invalid_persistence_options, FaultyValidatorAdapter, {:exit, :validator_failed}}} =
             Persistence.resolve_config({FaultyValidatorAdapter, failure: :exit}, nil)
  end
end
