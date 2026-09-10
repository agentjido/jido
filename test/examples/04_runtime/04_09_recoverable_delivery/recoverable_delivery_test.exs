defmodule JidoTest.Examples.Runtime.RecoverableDeliveryTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Examples.RecoverableDelivery, as: Example
  alias Jido.Examples.RecoverableDelivery.Deliver
  alias Jido.Examples.RecoverableDelivery.MemorySink, as: Sink

  setup %{jido: jido} do
    start_supervised!({Sink, jido: jido})
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    {:ok, store: store}
  end

  test "saved delivery intent resumes after loss without duplicating the external record", c do
    id = unique_id("example-recoverable-delivery")
    assert :ok = Sink.available(c.jido, false)
    server = start_example(c, id, false)

    assert {:ok, committed} = Example.record_and_deliver(server, "effect-1", 7)
    assert committed.state.delivery.pending == %{"effect-1" => 7}
    assert Sink.records(c.jido) == %{}

    server_ref = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    eventually(fn -> Jido.whereis_agent(c.jido, id) == nil end)

    assert :ok = Sink.available(c.jido, true)
    restored = start_example(c, id, :required)

    eventually(fn ->
      Server.agent(restored).state.delivery == %{
        pending: %{},
        completed: %{"effect-1" => 7}
      }
    end)

    assert Sink.records(c.jido) == %{"effect-1" => 7}
    assert Server.snapshot(restored).state_version == 2

    assert :ok = Sink.deliver(c.jido, %Deliver{effect_id: "effect-1", value: 7})
    assert Sink.records(c.jido) == %{"effect-1" => 7}
  end

  defp start_example(c, id, restore) do
    assert {:ok, server} =
             Jido.start_agent(c.jido, Example,
               id: id,
               persistence: c.store,
               restore: restore,
               restart: :temporary
             )

    server
  end
end
