defmodule JidoTest.Persistence.Contracts.Recovery do
  @moduledoc false

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias Jido.Persistence
      alias JidoTest.Persistence.{FaultAdapter, PersistentProbe}

      @tag persistence_contract: :recovery
      test "a rejected prewrite keeps the prior durable revision", c do
        control = start_supervised!({FaultAdapter, []})
        persistence = {FaultAdapter, delegate: c.store, control: control}
        id = unique_id("rejected-write")
        server = JidoTest.Persistence.Contracts.Recovery.start!(c, id, persistence)
        monitor = Process.monitor(server)

        FaultAdapter.configure(control, {:rejected, :contract_prewrite})
        {:ok, signal} = PersistentProbe.set_signal(%{value: 7})

        assert {:error, {:persistence_failed, {:rejected, :contract_prewrite}}} =
                 Server.call(server, signal)

        assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 5_000

        assert {:ok, %{state: %{value: 0}}, 0} =
                 Persistence.load_agent_with_revision(c.store, PersistentProbe, id,
                   instance: c.jido
                 )

        restored = JidoTest.Persistence.Contracts.Recovery.restore!(c, id)
        assert Server.snapshot(restored).state_version == 0
        assert Server.agent(restored).state.value == 0
      end

      @tag persistence_contract: :recovery
      test "a lost reply stops stale work and restores the stored candidate", c do
        control = start_supervised!({FaultAdapter, []})
        persistence = {FaultAdapter, delegate: c.store, control: control}
        id = unique_id("lost-write-reply")
        server = JidoTest.Persistence.Contracts.Recovery.start!(c, id, persistence)
        monitor = Process.monitor(server)

        FaultAdapter.configure(control, {:lost_reply, :contract_lost_reply})
        {:ok, signal} = PersistentProbe.set_and_emit_signal(%{value: 13})

        assert {:error, {:persistence_failed, {:indeterminate, :contract_lost_reply}}} =
                 Server.call(server, signal, context: %{observer: self()})

        assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 5_000
        refute_received {:signal, %{type: "test.persistence.probe.committed"}}

        assert {:ok, %{state: %{value: 13}}, 1} =
                 Persistence.load_agent_with_revision(c.store, PersistentProbe, id,
                   instance: c.jido
                 )

        restored = JidoTest.Persistence.Contracts.Recovery.restore!(c, id)
        assert Server.snapshot(restored).state_version == 1
        assert Server.agent(restored).state.value == 13
      end
    end
  end

  def start!(context, id, persistence) do
    {:ok, server} =
      Jido.start_agent(context.jido, JidoTest.Persistence.PersistentProbe,
        id: id,
        persistence: persistence,
        restore: false,
        restart: :temporary
      )

    server
  end

  def restore!(context, id) do
    {:ok, server} =
      Jido.thaw(context.jido, JidoTest.Persistence.PersistentProbe, id,
        persistence: context.store,
        restart: :temporary
      )

    server
  end
end
