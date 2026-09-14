defmodule JidoTest.System.Scenarios.Fencing do
  @moduledoc false
  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias JidoTest.RecoverableDeliveryAgent, as: Probe
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.Observability

      test "competing checkpoint writers have one winner and fence the stale live Agent", c do
        server = start_agent(c)
        initial = Server.agent(server)
        parent = self()

        tasks =
          for value <- 1..8 do
            Task.async(fn ->
              send(parent, {:writer_ready, self()})
              receive do: (:write -> :ok)
              candidate = %{initial | state: %{initial.state | value: value}}

              {Jido.Persistence.save_agent(c.store, candidate,
                 instance: c.jido,
                 namespace: c.namespace,
                 expected_revision: 0,
                 revision: 1
               ), candidate}
            end)
          end

        for _ <- tasks, do: assert_receive({:writer_ready, _}, 10_000)
        for task <- tasks, do: send(task.pid, :write)
        results = Enum.map(tasks, &Task.await(&1, 30_000))
        assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
        assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 7
        assert {:ok, ^winner, 1} = load(c, initial.id)
        monitor = Process.monitor(server)
        signal = Probe.record_and_deliver_signal!("stale", 99)
        assert {:error, {:persistence_failed, :conflict}} = Server.call(server, signal)
        assert_receive {:DOWN, ^monitor, :process, ^server, _}, 10_000
        Observability.assert_turn(c.observer, signal, :error, false)
        Observability.assert_persistence(c.observer, :conflict)
        assert Sink.records(c.jido) == %{}
        restored = start_agent(c, id: initial.id, restore: :required)
        assert Server.snapshot(restored) == %{agent: winner, state_version: 1}
        stop_agent(c, restored)
      end

      test "a tombstone fences a live writer and cannot replay effects on restore", c do
        server = start_agent(c)
        id = Server.agent(server).id

        assert :ok =
                 Jido.Persistence.delete_agent(c.store, Probe, id,
                   instance: c.jido,
                   namespace: c.namespace
                 )

        monitor = Process.monitor(server)
        signal = Probe.record_and_deliver_signal!("deleted", 99)
        assert {:error, {:persistence_failed, :conflict}} = Server.call(server, signal)
        assert_receive {:DOWN, ^monitor, :process, ^server, _}, 10_000
        assert {:error, :deleted} = load(c, id)

        assert {:error, :deleted} =
                 Jido.start_agent(c.jido, Probe, id: id, persistence: c.store, restore: :required)

        Observability.assert_turn(c.observer, signal, :error, false)
        assert Sink.records(c.jido) == %{}
      end
    end
  end
end
