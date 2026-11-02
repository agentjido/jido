defmodule Jido.Signal.Bus.StoreTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Bus.Store

  defmodule Adapter do
    def init(opts) do
      case Keyword.get(opts, :result, :ok) do
        :ok -> {:ok, :initial}
        :error -> {:error, :unavailable}
        :invalid -> :invalid
        :raise -> raise "failed"
      end
    end

    def read(mode, state) do
      case mode do
        :ok -> {:ok, {mode, state}}
        :error -> {:error, :failed}
        :invalid -> :invalid
        :raise -> raise "failed"
        :throw -> throw(:failed)
      end
    end

    def write(value, state) do
      case value do
        :ok -> {:ok, {:updated, state}}
        :error -> {:error, :failed}
        :invalid -> :invalid
        :raise -> raise "failed"
      end
    end
  end

  test "normalizes Store initialization" do
    assert {:ok, :initial} = Store.init_adapter(Adapter, [])

    assert {:error, {:store_init_failed, :unavailable}} =
             Store.init_adapter(Adapter, result: :error)

    assert {:error, {:store_init_failed, {:invalid_return, :invalid}}} =
             Store.init_adapter(Adapter, result: :invalid)

    assert {:error, {:store_init_failed, {:exception, %RuntimeError{message: "failed"}}}} =
             Store.init_adapter(Adapter, result: :raise)
  end

  test "normalizes read callbacks" do
    assert {:ok, {:ok, :state}} = Store.read(Adapter, :state, :read, [:ok])
    assert {:error, {:store_error, :read, :failed}} = Store.read(Adapter, :state, :read, [:error])

    assert {:error, {:store_error, :read, {:invalid_return, :invalid}}} =
             Store.read(Adapter, :state, :read, [:invalid])

    assert {:error, {:store_error, :read, {:exception, %RuntimeError{}}}} =
             Store.read(Adapter, :state, :read, [:raise])

    assert {:error, {:store_error, :read, {:throw, :failed}}} =
             Store.read(Adapter, :state, :read, [:throw])

    state = %{store_module: Adapter, store_state: :state}
    assert {:ok, {:ok, :state}} = Store.read(state, :read, [:ok])
  end

  test "normalizes write callbacks and updates only Store state" do
    state = %{store_module: Adapter, store_state: :state, other: :kept}

    assert {:ok, %{store_state: {:updated, :state}, other: :kept}} =
             Store.write(state, :write, [:ok])

    assert {:error, {:store_error, :write, :failed}} = Store.write(state, :write, [:error])

    assert {:error, {:store_error, :write, {:invalid_return, :invalid}}} =
             Store.write(state, :write, [:invalid])

    assert {:error, {:store_error, :write, {:exception, %RuntimeError{}}}} =
             Store.write(state, :write, [:raise])
  end
end
