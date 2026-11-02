defmodule Jido.Signal.Dispatch.PubSubTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Dispatch

  defmodule FailingAdapter do
    @behaviour Phoenix.PubSub.Adapter

    @impl true
    def child_spec(opts) do
      name = Keyword.fetch!(opts, :adapter_name)
      %{id: name, start: {Agent, :start_link, [fn -> nil end, [name: name]]}}
    end

    @impl true
    def node_name(_name), do: "failing"

    @impl true
    def broadcast(_name, _topic, _message, _dispatcher),
      do: {:error, :cluster_unavailable}

    @impl true
    def direct_broadcast(_name, _node, _topic, _message, _dispatcher),
      do: {:error, :cluster_unavailable}
  end

  test "parses the PubSub target with Zoi" do
    assert {:ok, {:pubsub, opts}} =
             Dispatch.validate_opts({:pubsub, target: __MODULE__, topic: "events.created"})

    assert opts == [target: __MODULE__, topic: "events.created"]

    for invalid <- [
          {:pubsub, topic: "events.created"},
          {:pubsub, target: nil, topic: "events.created"},
          {:pubsub, target: __MODULE__},
          {:pubsub, target: __MODULE__, topic: :events},
          {:pubsub, target: __MODULE__, topic: "events", unknown: true}
        ] do
      assert {:error, _reason} = Dispatch.validate_opts(invalid)
    end
  end

  test "broadcasts a Signal on the selected topic" do
    name = Module.concat(__MODULE__, "Server#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: name})
    :ok = Phoenix.PubSub.subscribe(name, "orders")
    signal = Signal.new!("order.created", %{id: "ord-1"}, source: "/test")

    assert :ok = Dispatch.dispatch(signal, {:pubsub, target: name, topic: "orders"})
    assert_received ^signal
  end

  test "keeps topics isolated" do
    name = Module.concat(__MODULE__, "Isolated#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: name})
    :ok = Phoenix.PubSub.subscribe(name, "wanted")
    signal = Signal.new!("order.created", %{}, source: "/test")

    assert :ok = Dispatch.dispatch(signal, {:pubsub, target: name, topic: "other"})
    refute_received ^signal
  end

  test "returns a stable error when the PubSub server is not running" do
    signal = Signal.new!("order.created", %{}, source: "/test")

    assert {:error, :pubsub_not_found} =
             Dispatch.dispatch(
               signal,
               {:pubsub, target: __MODULE__.Missing, topic: "orders"}
             )
  end

  test "returns a stable error when the target is a non-PubSub Registry" do
    name = Module.concat(__MODULE__, "Registry#{System.unique_integer([:positive])}")
    start_supervised!({Registry, keys: :unique, name: name})
    signal = Signal.new!("order.created", %{}, source: "/test")

    assert {:error, :pubsub_not_found} =
             Dispatch.dispatch(signal, {:pubsub, target: name, topic: "orders"})
  end

  test "propagates PubSub adapter broadcast failures" do
    name = Module.concat(__MODULE__, "Failing#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: name, adapter: FailingAdapter})
    signal = Signal.new!("order.created", %{}, source: "/test")

    assert {:error, :cluster_unavailable} =
             Dispatch.dispatch(signal, {:pubsub, target: name, topic: "orders"})
  end
end
