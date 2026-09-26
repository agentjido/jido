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
      {:ok, route_signal_1} = Example.wait_for_signal(%{reason: reason})

      assert {:ok, _} =
               Jido.AgentServer.call(c.server, route_signal_1, [])

      assert Example.view(c.server, c.table).committed.waiting == reason
    end

    {:ok, route_signal_2} = Example.cancel_wait_signal(%{})

    assert {:ok, _} =
             Jido.AgentServer.call(c.server, route_signal_2, [])

    assert Example.view(c.server, c.table).committed.status == :cancelled
    assert Example.view(c.server, c.table).committed.waiting == :none
  end

  test "live progress stays bounded while committed state is unchanged", c do
    alias JidoTest.Examples.ProgressObservationWorker

    {:ok, server} = Jido.start_agent(c.jido, ProgressObservationWorker)
    owner = self()

    task =
      Task.async(fn ->
        {:ok, route_signal_3} = ProgressObservationWorker.work_signal(%{})

        Jido.AgentServer.call(server, route_signal_3,
          context: %{progress_table: c.table, observer: owner}
        )
      end)

    assert_receive {:working, worker}, 1000
    view = Example.view(server, c.table)
    assert view.committed.status == :idle
    assert Enum.map(view.progress.events, &elem(&1, 0)) == ~c"\b\t\n"
    assert view.progress.missed == 7
    assert :ets.info(c.table, :size) == 5
    send(worker, :release)
    assert {:ok, result} = Task.await(task)
    assert result.state.result == "report"
    assert Example.view(server, c.table, 10).progress.events == []
  end

  test "observer loss and reconnect preserve the terminal result", c do
    :ok = stop_supervised(Buffer)

    {:ok, route_signal_4} = Example.work_signal(%{})

    assert {:ok, result} =
             Jido.AgentServer.call(c.server, route_signal_4, context: %{progress_table: c.table})

    replacement = start_supervised!({Buffer, 3})
    view = Example.view(c.server, Buffer.table(replacement))
    assert view.progress.events == []
    assert view.committed == result.state
    assert view.committed.status == :completed
  end

  test "cancellation stops active work without committing partial progress", c do
    alias JidoTest.Examples.ProgressObservationWorker

    {:ok, server} = Jido.start_agent(c.jido, ProgressObservationWorker)
    owner = self()

    task =
      Task.async(fn ->
        {:ok, route_signal_5} = ProgressObservationWorker.work_signal(%{})

        Jido.AgentServer.call(server, route_signal_5,
          context: %{progress_table: c.table, observer: owner}
        )
      end)

    assert_receive {:working, worker}, 1000
    ref = Process.monitor(worker)
    assert :ok = Jido.AgentServer.cancel(server)
    assert {:error, _} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
    assert Example.view(server, c.table).committed.status == :idle

    {:ok, route_signal_6} = Example.cancel_wait_signal(%{})

    assert {:ok, _} =
             Jido.AgentServer.call(c.server, route_signal_6, [])

    assert Example.view(c.server, c.table).committed.status == :cancelled
  end

  test "terminal state survives persistent Agent replacement and a new observer", c do
    alias Jido.Examples.PersistenceProbeStore
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}

    assert {:ok, server} =
             Jido.start_agent(c.jido, Example, id: "saved-progress", persistence: store)

    {:ok, route_signal_7} = Example.work_signal(%{})

    assert {:ok, agent} =
             Jido.AgentServer.call(server, route_signal_7, context: %{progress_table: c.table})

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
