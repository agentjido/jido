defmodule Jido.Signal.Dispatch.AdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias Jido.Signal.Dispatch.Adapter

  defmodule CustomAdapter do
    @behaviour Adapter

    @impl true
    def options_schema do
      Zoi.keyword(
        [
          target: Zoi.pid() |> Zoi.required(),
          label: Zoi.string() |> Zoi.default("default"),
          fail: Zoi.boolean() |> Zoi.default(false)
        ],
        unrecognized_keys: :error
      )
    end

    @impl true
    def deliver(_signal, opts) do
      if Keyword.fetch!(opts, :fail) do
        {:error, :custom_failure}
      else
        send(Keyword.fetch!(opts, :target), {:custom_delivery, Keyword.fetch!(opts, :label)})
        :ok
      end
    end
  end

  defmodule InvalidSchemaAdapter do
    @behaviour Adapter

    @impl true
    def options_schema, do: :not_a_zoi_schema

    @impl true
    def deliver(_signal, _opts), do: :ok
  end

  defmodule RaisingSchemaAdapter do
    @behaviour Adapter

    @impl true
    def options_schema, do: raise("schema failed")

    @impl true
    def deliver(_signal, _opts), do: :ok
  end

  defmodule IncompleteAdapter do
    def deliver(_signal, _opts), do: :ok
  end

  defmodule OtherBehaviour do
    @callback marker() :: :ok
  end

  defmodule AdapterDeclaredLast do
    @behaviour OtherBehaviour
    @behaviour Adapter

    @impl OtherBehaviour
    def marker, do: :ok

    @impl Adapter
    def options_schema, do: CustomAdapter.options_schema()

    @impl Adapter
    def deliver(signal, opts), do: CustomAdapter.deliver(signal, opts)
  end

  defmodule AdapterDeclaredFirst do
    @behaviour Adapter
    @behaviour OtherBehaviour

    @impl OtherBehaviour
    def marker, do: :ok

    @impl Adapter
    def options_schema, do: CustomAdapter.options_schema()

    @impl Adapter
    def deliver(signal, opts), do: CustomAdapter.deliver(signal, opts)
  end

  defmodule UndeclaredAdapter do
    def options_schema, do: CustomAdapter.options_schema()
    def deliver(signal, opts), do: CustomAdapter.deliver(signal, opts)
  end

  test "requires the schema and delivery callbacks" do
    callbacks = Adapter.behaviour_info(:callbacks)
    assert {:options_schema, 0} in callbacks
    assert {:deliver, 2} in callbacks
    refute {:validate_opts, 1} in callbacks
  end

  test "parses custom adapter options with Zoi" do
    assert {:ok, {CustomAdapter, opts}} =
             Dispatch.validate_opts({CustomAdapter, target: self()})

    assert opts == [target: self(), label: "default", fail: false]

    assert {:error, reason} =
             Dispatch.validate_opts({CustomAdapter, target: self(), unknown: true})

    assert reason =~ "unrecognized key"
  end

  test "delivers through a custom adapter" do
    signal = Signal.new!("custom.dispatch", %{}, source: "/test")

    assert :ok =
             Dispatch.dispatch(signal, {CustomAdapter, target: self(), label: "accepted"})

    assert_received {:custom_delivery, "accepted"}

    assert {:error, :custom_failure} =
             Dispatch.dispatch(signal, {CustomAdapter, target: self(), fail: true})
  end

  test "accepts the adapter behaviour in either declaration order" do
    signal = Signal.new!("custom.dispatch", %{}, source: "/test")

    for adapter <- [AdapterDeclaredLast, AdapterDeclaredFirst] do
      assert {:ok, {^adapter, opts}} = Dispatch.validate_opts({adapter, target: self()})
      assert opts == [target: self(), label: "default", fail: false]
      assert :ok = Dispatch.dispatch(signal, {adapter, target: self(), label: "accepted"})
      assert_received {:custom_delivery, "accepted"}
    end
  end

  test "rejects invalid adapter modules and schemas" do
    assert {:error, reason} = Dispatch.validate_opts({IncompleteAdapter, []})
    assert reason =~ "not a valid adapter"

    assert {:error, reason} = Dispatch.validate_opts({UndeclaredAdapter, target: self()})
    assert reason =~ "not a valid adapter"

    assert {:error, {:invalid_options_schema, InvalidSchemaAdapter}} =
             Dispatch.validate_opts({InvalidSchemaAdapter, []})

    assert {:error, {:invalid_options_schema, "schema failed"}} =
             Dispatch.validate_opts({RaisingSchemaAdapter, []})
  end
end
