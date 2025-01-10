defmodule Jido.Bus.PubSubAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Bus
  alias Jido.Bus.Adapters.PubSub

  describe "child_spec/2" do
    test "returns children and configured bus" do
      {:ok, children, bus} = PubSub.child_spec(MyContext, [])

      assert [
               {Phoenix.PubSub, [name: MyContext.PubSub]}
             ] = children

      assert %Bus{
               id: "Elixir.MyContext",
               adapter: PubSub,
               config: [pubsub_name: MyContext.PubSub]
             } = bus
    end

    test "uses provided name" do
      {:ok, children, bus} = PubSub.child_spec(MyContext, name: MyCustomName)

      assert [
               {Phoenix.PubSub, [name: MyCustomName.PubSub]}
             ] = children

      assert %Bus{
               id: "Elixir.MyCustomName",
               adapter: PubSub,
               config: [pubsub_name: MyCustomName.PubSub]
             } = bus
    end
  end

  describe "publish/5" do
    setup do
      {:ok, children, bus} = PubSub.child_spec(MyContext, [])
      start_supervised!(hd(children))
      {:ok, bus: bus}
    end

    test "broadcasts signals to subscribers", %{bus: bus} do
      :ok = PubSub.subscribe(bus, "stream-1")
      signal = %{id: 1, data: "test"}

      :ok = PubSub.publish(bus, "stream-1", 0, [signal], [])

      assert_receive {:signal, ^signal}
    end

    test "broadcasts multiple signals in order", %{bus: bus} do
      :ok = PubSub.subscribe(bus, "stream-1")
      signals = [%{id: 1}, %{id: 2}, %{id: 3}]

      :ok = PubSub.publish(bus, "stream-1", 0, signals, [])

      Enum.each(signals, fn signal ->
        assert_receive {:signal, ^signal}
      end)
    end
  end

  describe "subscribe/2" do
    setup do
      {:ok, children, bus} = PubSub.child_spec(MyContext, [])
      start_supervised!(hd(children))
      {:ok, bus: bus}
    end

    test "subscribes to stream", %{bus: bus} do
      assert :ok = PubSub.subscribe(bus, "stream-1")
    end
  end

  describe "unsubscribe/2" do
    setup do
      {:ok, children, bus} = PubSub.child_spec(MyContext, [])
      start_supervised!(hd(children))
      {:ok, bus: bus}
    end

    test "unsubscribes from stream", %{bus: bus} do
      :ok = PubSub.subscribe(bus, "stream-1")
      assert :ok = PubSub.unsubscribe(bus, "stream-1")

      PubSub.publish(bus, "stream-1", 0, [%{id: 1}], [])
      refute_receive {:signal, _}
    end
  end

  describe "unsupported operations" do
    setup do
      {:ok, children, bus} = PubSub.child_spec(MyContext, [])
      start_supervised!(hd(children))
      {:ok, bus: bus}
    end

    test "replay returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} = PubSub.replay(bus, "stream-1", 0, 100)
    end

    test "subscribe_persistent returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} =
               PubSub.subscribe_persistent(bus, "stream-1", "sub1", self(), :origin, [])
    end

    test "ack returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} = PubSub.ack(bus, self(), %{})
    end

    test "read_snapshot returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} = PubSub.read_snapshot(bus, "source-1")
    end

    test "record_snapshot returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} = PubSub.record_snapshot(bus, %{})
    end

    test "delete_snapshot returns not implemented", %{bus: bus} do
      assert {:error, :not_implemented} = PubSub.delete_snapshot(bus, "source-1")
    end
  end
end
