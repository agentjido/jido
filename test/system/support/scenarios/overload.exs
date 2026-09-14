defmodule JidoTest.System.Scenarios.Overload do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Jido.AgentServer, as: Server
      alias Jido.Plugin.Bus.Client
      alias Jido.Signal.Bus
      alias JidoTest.System.{BusAgent, ControlledAgent, Observability}

      test "overload, caller timeout, Bus replacement, and worker death account for every request",
           c do
        bus = start_supervised!({Bus, name: :system_bus, jido: c.jido}, id: :system_bus)

        server =
          start_agent(c, module: BusAgent, max_postponed_signals: 5, turn_timeout: :infinity)

        assert {:ok, _} = Server.call(server, ControlledAgent.signal(1))
        id = Server.agent(server).id
        gate = make_ref()
        held = ControlledAgent.signal(99, gate: gate, observer: self())
        active = Server.send_request(server, held, :infinity)
        assert_receive {:work_held, ^gate, worker}, 10_000
        worker_monitor = Process.monitor(worker)
        expired = ControlledAgent.signal(55)

        caller =
          Task.async(fn ->
            try do
              Server.call(server, expired, 100)
            catch
              :exit, reason -> reason
            end
          end)

        assert {:timeout, _} = Task.await(caller, 10_000)
        assert Server.status(server).admission.postponed == 1
        accepted = for value <- 1..4, do: ControlledAgent.signal(value)
        requests = Enum.map(accepted, &Server.send_request(server, &1, :infinity))
        assert Server.status(server).admission.postponed == 5
        excess = for value <- 1..10, do: ControlledAgent.signal(-value)

        for signal <- excess do
          assert {:error, {:overloaded, %{limit: 5, postponed: 5}}} = Server.call(server, signal)
        end

        dropped = ControlledAgent.signal(-99, secret: "must-not-appear-in-logs")
        :ok = Server.cast(server, dropped)

        log =
          Observability.await_log(c.observer, fn log ->
            log.meta[:signal_id] == dropped.id
          end)

        assert log.level == :warning
        refute inspect(log) =~ "must-not-appear-in-logs"

        bus_monitor = Process.monitor(bus)
        stop_supervised!(:system_bus)
        assert_receive {:DOWN, ^bus_monitor, :process, ^bus, _}, 10_000
        replacement = start_supervised!({Bus, name: :system_bus, jido: c.jido}, id: :system_bus)
        assert replacement != bus
        client = Server.children(server)[{:plugin, Client}].pid
        assert :ok = Client.await_ready(client, [])

        Process.exit(worker, :kill)
        assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 10_000
        assert {:reply, {:error, _}} = Server.receive_response(active, 10_000)

        for {request, value} <- Enum.with_index(requests, 1) do
          assert {:reply, {:ok, %{state: %{value: ^value}}}} =
                   Server.receive_response(request, 10_000)
        end

        signal = ControlledAgent.signal(77)
        assert {:ok, [_]} = Bus.publish(replacement, [signal])
        Observability.await_turn(c.observer, server, 6)
        assert Server.snapshot(server).state_version == 6
        assert {:ok, %{state: %{value: 77}}, 6} = load(c, id, BusAgent)
        assert %{postponed: 0, message_queue_len: 0} = Server.status(server).admission
        stop_agent(c, server)
        assert_empty_agent_pool(c)
        assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

        rejected =
          for {_, [:jido, :agent, :admission, :rejected], measurements, metadata} <-
                Observability.events(c.observer),
              do: {metadata.source_signal_id, metadata.admission_reason, measurements.queue_depth}

        expected = [
          {expired.id, :deadline_expired, 4}
          | Enum.map([dropped | excess], &{&1.id, :overloaded, 5})
        ]

        assert Enum.sort(rejected) == Enum.sort(expected)

        for accepted_signal <- [signal | accepted],
            do: Observability.assert_turn(c.observer, accepted_signal, :ok, true)

        turns =
          for {_, [:jido, :agent, :turn, :stop], _, metadata} <- Observability.events(c.observer),
              do: metadata

        assert length(turns) == 7
        assert Enum.count(turns, & &1.committed?) == 6

        assert [%{status: :error, committed?: false}] =
                 Enum.filter(turns, &(&1.source_signal_id == held.id))

        settled =
          for {_, [:jido, :agent, :turn, :settled], _, metadata} <-
                Observability.events(c.observer),
              do: metadata.turn_id

        assert Enum.sort(settled) == Enum.sort(Enum.map(turns, & &1.turn_id))
      end
    end
  end
end
