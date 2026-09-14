defmodule JidoTest.System.Scenarios.Restoration do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Jido.AgentServer, as: Server
      alias Jido.Persistence
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.{ControlledAgent, FaultAdapter, MigrationAgent, Observability}

      for restore <- [:required, :if_found] do
        @restore_mode restore
        test "#{@restore_mode} refuses an unsupported Plugin record without a reset", c do
          server = start_agent(c, module: MigrationAgent)
          assert {:ok, saved} = Server.call(server, ControlledAgent.signal(7))
          stop_agent(c, server)
          {adapter, opts} = c.store
          key = Persistence.agent_key(Jido.Agent.Ref.new!(namespace: c.namespace, id: saved.id))
          assert {:ok, original} = read_bytes(adapter, key, opts)
          record = :erlang.binary_to_term(original, [:safe])
          assert record.checkpoint.state.owned == %{format: 1, value: 0}
          incompatible = put_in(record.checkpoint.state.owned, %{format: 99, value: 0})
          bytes = :erlang.term_to_binary(incompatible)
          assert :ok = adapter.put(key, bytes, opts)

          assert {:error, :unsupported_plugin_format} =
                   Jido.start_agent(c.jido, MigrationAgent,
                     id: saved.id,
                     persistence: c.store,
                     restore: @restore_mode
                   )

          assert {:ok, ^bytes} = read_bytes(adapter, key, opts)
          assert Jido.whereis_agent(c.jido, saved.id) == nil
          assert_empty_agent_pool(c)
          Observability.assert_persistence(c.observer, :error)

          # Repair only the owned fixture bytes. A subsequent activation must
          # load the original state, not a default written by the failed load.
          assert :ok = adapter.put(key, original, opts)
          restored = start_agent(c, module: MigrationAgent, id: saved.id, restore: :required)
          assert Server.snapshot(restored) == %{agent: saved, state_version: 1}
          stop_agent(c, restored)
          assert Sink.attempts(c.jido) == []
        end
      end

      test "deletion after a restore read prevents stale activation", c do
        server = start_agent(c, module: ControlledAgent)
        assert {:ok, saved} = Server.call(server, ControlledAgent.signal(7))
        stop_agent(c, server)
        FaultAdapter.arm(c.control, {:read, {:after_read, self()}})

        activation =
          Task.async(fn ->
            Jido.start_agent(c.jido, ControlledAgent,
              id: saved.id,
              persistence: c.persistence,
              restart: :temporary,
              restore: :required
            )
          end)

        assert_receive {:record_read, reader, {:ok, _}}, 10_000

        assert :ok =
                 Persistence.delete_agent(c.store, ControlledAgent, saved.id,
                   instance: c.jido,
                   namespace: c.namespace
                 )

        send(reader, :release_read)
        assert {:error, :deleted} = Task.await(activation, 10_000)
        assert Jido.whereis_agent(c.jido, saved.id) == nil
        assert_empty_agent_pool(c)
        assert {:error, :deleted} = load(c, saved.id, ControlledAgent)
        Observability.assert_persistence(c.observer, :not_found)
        assert Sink.attempts(c.jido) == []
      end
    end
  end
end
