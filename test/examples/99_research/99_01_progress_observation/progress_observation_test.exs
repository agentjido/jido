defmodule JidoTest.Examples.ProgressObservationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.ProgressObservation, as: Example
  alias Example.Buffer

  setup %{jido: jido} do
    buffer = start_supervised!({Buffer, 3})
    {:ok, server} = Jido.start_agent(jido, Example)
    %{server: server, buffer: buffer, table: Buffer.table(buffer)}
  end

  test "waiting reasons are queryable and cancellation clears the wait", c do
    for reason <- [:approval, :child, :retry, :delivery] do
      assert {:ok, _} = Example.wait_for(c.server, reason)
      assert Example.view(c.server, c.table).committed.waiting == reason
    end

    assert {:ok, _} = Example.cancel_wait(c.server)
    assert Example.view(c.server, c.table).committed.status == :cancelled
    assert Example.view(c.server, c.table).committed.waiting == :none
  end

  test "live progress stays bounded while committed state is unchanged", c do
    owner = self()

    task =
      Task.async(fn ->
        Example.work(c.server,
          context: %{
            report: &Buffer.publish(c.table, &1),
            barrier: fn ->
              send(owner, {:working, self()})

              receive do
                :release -> :ok
              end
            end
          }
        )
      end)

    assert_receive {:working, worker}, 1_000
    view = Example.view(c.server, c.table)
    assert view.committed.status == :idle
    assert Enum.map(view.progress.events, &elem(&1, 0)) == [8, 9, 10]
    assert view.progress.missed == 7
    assert :ets.info(c.table, :size) == 5
    send(worker, :release)
    assert {:ok, result} = Task.await(task)
    assert result.state.result == "report"
    assert Example.view(c.server, c.table, 10).progress.events == []
  end

  test "observer loss and reconnect preserve the terminal result", c do
    :ok = stop_supervised(Buffer)

    assert {:ok, result} =
             Example.work(c.server,
               context: %{report: &Buffer.publish(c.table, &1), barrier: fn -> :ok end}
             )

    replacement = start_supervised!({Buffer, 3})
    view = Example.view(c.server, Buffer.table(replacement))
    assert view.progress.events == []
    assert view.committed == result.state
    assert view.committed.status == :completed
  end

  test "cancellation stops active work without committing partial progress", c do
    owner = self()

    task =
      Task.async(fn ->
        Example.work(c.server,
          context: %{
            report: &Buffer.publish(c.table, &1),
            barrier: fn ->
              send(owner, {:working, self()})

              receive do
                :release -> :ok
              end
            end
          }
        )
      end)

    assert_receive {:working, worker}, 1_000
    ref = Process.monitor(worker)
    assert :ok = Jido.AgentServer.cancel(c.server)
    assert {:error, _} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000
    assert Example.view(c.server, c.table).committed.status == :idle
    assert {:ok, _} = Example.cancel_wait(c.server)
    assert Example.view(c.server, c.table).committed.status == :cancelled
  end

  test "terminal state survives persistent Agent replacement and a new observer", c do
    alias Jido.Examples.PersistenceProbeStore
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}

    assert {:ok, server} =
             Jido.start_agent(c.jido, Example, id: "saved-progress", persistence: store)

    assert {:ok, agent} =
             Example.work(server,
               context: %{report: &Buffer.publish(c.table, &1), barrier: fn -> :ok end}
             )

    assert :ok = Jido.hibernate(c.jido, server)
    assert {:ok, replacement} = Jido.thaw(c.jido, Example, "saved-progress", persistence: store)
    assert :ok = stop_supervised(Buffer)
    buffer = start_supervised!({Buffer, 3})
    view = Example.view(replacement, Buffer.table(buffer))
    assert view.committed == agent.state
    assert view.committed.result == "report"
    assert view.progress.events == []
  end
end
