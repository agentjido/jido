Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/signal_journey.exs", __DIR__)

for adapter <- [:ets, :file, :ecto] do
  defmodule Module.concat(JidoTest.System.SignalJourney, Macro.camelize(to_string(adapter))) do
    use JidoTest.System.Case, async: false
    @moduletag :system
    @moduletag adapter: adapter
    alias Jido.AgentServer, as: Server
    alias Jido.Plugin.Bus.Client
    alias Jido.Signal.{Bus, Serialization}
    alias Jido.Tracing.Trace
    alias JidoTest.RecoverableDeliverySink, as: Sink
    alias JidoTest.System.{AckStore, DurableJourneyAgent, NormalJourneyAgent, Observability}

    for boundary <- [:normal, :ack_retry, :replay] do
      @boundary boundary
      @tag scenario: boundary
      test "JSON, routing, Flow, commit and effect agree at #{@boundary}", c do
        {:ok, memory} = Jido.Signal.Bus.Store.Memory.init([])
        owner = self()

        store =
          start_supervised!(
            Supervisor.child_spec(
              {Agent, fn -> %{store: memory, fail_ack: false, owner: owner} end},
              id: :journey_store
            )
          )

        bus = start_bus(c, store)
        module = if @boundary == :normal, do: NormalJourneyAgent, else: DurableJourneyAgent
        server = start_agent(c, module: module)
        assert :ok = Client.await_ready(client(server), [])
        trace = Trace.new_root()

        signal =
          Jido.Signal.new!("system.journey", %{"effect_id" => "journey", "value" => 7},
            source: "/system"
          )

        {:ok, signal} = Trace.put(signal, trace)
        assert {:ok, json} = Serialization.serialize(signal)
        assert {:ok, decoded} = Serialization.deserialize(json)
        assert decoded.id == signal.id

        assert {:error, _} =
                 Serialization.deserialize(~s({"specversion":"1.0","type":"system.journey"}))

        if @boundary != :normal, do: Agent.update(store, &%{&1 | fail_ack: true})
        assert {:ok, [record]} = Bus.publish(bus, [decoded])
        completed(c, server, %{"journey" => 14})
        assert Server.agent(server).state.value == 14
        assert {:ok, saved, 2} = load(c, Server.agent(server).id, module)
        assert saved == Server.agent(server)

        if @boundary != :normal do
          assert_receive {:ack_failed, ^bus, cursor}, 10_000
          assert cursor == record.cursor
          old_client = client(server)
          pending = :sys.get_state(old_client).pending
          assert pending.stage == :ack
          assert Agent.get(store, & &1.store.subscriptions["journey"]["cursor"]) == 0

          if @boundary == :ack_retry do
            # Drive the actual scheduled retry message after an explicit state
            # barrier. No elapsed-time assumption controls this fault.
            send(old_client, {:retry_record, pending.token})
            assert :sys.get_state(old_client).pending == nil
          else
            snapshot = Server.snapshot(server)
            kill_agent(c, server)
            stop_supervised!(:journey_bus)
            _replacement_bus = start_bus(c, store)

            result =
              Jido.start_agent(c.jido, module,
                id: saved.id,
                persistence: c.persistence,
                restore: :required,
                restart: :temporary
              )

            replacement =
              case result do
                {:ok, pid} ->
                  pid

                error ->
                  flunk(
                    "SYSTEM-BUS-01: durable replay could not finish Agent startup: #{inspect(error)}. Bus cursor=#{Agent.get(store, & &1.store.subscriptions["journey"]["cursor"])}; saved checkpoint=#{inspect(load(c, saved.id, module), limit: 3)}"
                  )
              end

            assert :ok = Client.await_ready(client(replacement), [])
            Observability.await_turn(c.observer, replacement, 3)
            assert Server.snapshot(replacement).agent == snapshot.agent
            assert {:ok, ^saved, 3} = load(c, saved.id, module)
            assert :sys.get_state(client(replacement)).pending == nil
            stop_agent(c, replacement)
          end

          assert Agent.get(store, & &1.store.subscriptions["journey"]["cursor"]) == record.cursor
        end

        if Process.alive?(server), do: stop_agent(c, server)
        assert_empty_agent_pool(c)
        assert Sink.records(c.jido) == %{"journey" => 14}
        assert length(Sink.attempts(c.jido)) == 1

        turns =
          for {_, [:jido, :agent, :turn, :stop], _, meta} <- Observability.events(c.observer),
              meta[:source_signal_id] == signal.id,
              do: meta

        assert length(turns) == if(@boundary == :replay, do: 2, else: 1)
        assert Enum.all?(turns, &(&1.trace_id == trace.trace_id and &1.committed?))

        assert Enum.any?(Observability.events(c.observer), fn
                 {_, [:jido, :agent, :directive, :stop], _, meta} ->
                   meta[:trace_id] == trace.trace_id

                 _ ->
                   false
               end)
      end
    end

    defp start_bus(c, store),
      do:
        start_supervised!(
          Supervisor.child_spec(
            {Bus, name: :journey, jido: c.jido, store: AckStore, store_opts: [state: store]},
            id: :journey_bus
          )
        )

    defp client(server) do
      Server.children(server)
      |> Map.values()
      |> Enum.find_value(fn child -> if child.module == Client, do: child.pid end)
    end
  end
end
