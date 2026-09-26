defmodule JidoTest.System.Scenarios.Restoration do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Jido.AgentServer, as: Server
      alias Jido.Persistence
      alias JidoTest.RecoverableDeliveryAgent, as: DeliveryAgent
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

      test "deletion after a restore read fences its next commit and effects", c do
        server = start_agent(c)
        saved = Server.agent(server)
        stop_agent(c, server)
        FaultAdapter.arm(c.control, {:read, {:after_read, self()}})

        activation =
          Task.async(fn ->
            Jido.start_agent(c.jido, DeliveryAgent,
              id: saved.id,
              persistence: c.persistence,
              restart: :temporary,
              restore: :required
            )
          end)

        assert_receive {:record_read, reader, {:ok, _}}, 10_000

        assert :ok =
                 Persistence.delete_agent(c.store, DeliveryAgent, saved.id,
                   instance: c.jido,
                   namespace: c.namespace
                 )

        send(reader, :release_read)
        # This is the snapshot read, not the removed identity-discovery probe.
        # A read does not reserve the record against a later deletion.
        assert {:ok, restored} = Task.await(activation, 10_000)
        assert Server.snapshot(restored) == %{agent: saved, state_version: 0}
        monitors = monitor_agent_tree(c, restored)

        {:ok, signal} =
          DeliveryAgent.record_and_deliver_signal(%{effect_id: "deleted-restore", value: 99})

        assert {:error, {:persistence_failed, :conflict}} = Server.call(restored, signal)
        await_down(monitors)
        Observability.assert_turn(c.observer, signal, :error, false)
        Observability.assert_persistence(c.observer, :conflict)

        assert {:error, :deleted} =
                 Jido.start_agent(c.jido, DeliveryAgent,
                   id: saved.id,
                   persistence: c.persistence,
                   restore: :required
                 )

        assert Jido.whereis_agent(c.jido, saved.id) == nil
        assert_empty_agent_pool(c)
        assert {:error, :deleted} = load(c, saved.id, DeliveryAgent)
        Observability.assert_persistence(c.observer, :not_found)
        assert Sink.attempts(c.jido) == []
      end
    end
  end
end
