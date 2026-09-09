defmodule JidoTest.Examples.Runtime.RecoverableDeliveryTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Examples.RecoverableDelivery, as: Example
  alias Jido.Examples.RecoverableDelivery.Sink

  setup %{jido: jido} do
    start_supervised!({Sink, jido: jido, observer: self()})
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    {:ok, store: store}
  end

  test "saved delivery intent resumes after loss without duplicating the external record", c do
    id = unique_id("example-recoverable-delivery")
    assert :ok = Sink.hold(c.jido, :after_write)
    server = start_example(c, id, false)

    assert {:ok, committed} = Example.record_and_deliver(server, "effect-1", 7)
    assert_receive {:effect_attempt, "effect-1", task}, 1_000
    eventually(fn -> Sink.records(c.jido) == %{"effect-1" => 7} end)
    assert committed.state.delivery.pending == %{"effect-1" => 7}

    server_ref = Process.monitor(server)
    task_ref = Process.monitor(task)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_ref, :process, ^server, :killed}, 1_000
    assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}, 1_000
    eventually(fn -> Jido.whereis_agent(c.jido, id) == nil end)

    assert :ok = Sink.hold(c.jido, :none)
    restored = start_example(c, id, :required)
    assert_receive {:effect_attempt, "effect-1", new_task}, 1_000
    assert new_task != task

    eventually(fn ->
      Server.agent(restored).state.delivery == %{
        pending: %{},
        completed: %{"effect-1" => 7}
      }
    end)

    assert Sink.records(c.jido) == %{"effect-1" => 7}
    assert Server.snapshot(restored).state_version == 2
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
