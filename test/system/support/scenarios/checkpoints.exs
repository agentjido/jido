defmodule JidoTest.System.Scenarios.Checkpoints do
  @moduledoc false
  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias JidoTest.RecoverableDeliveryAgent, as: Probe
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.{FaultAdapter, Observability}

      for stage <- [:before_write, :after_write] do
        @stage stage
        test "Agent crash at checkpoint #{@stage} preserves the exact durable revision", c do
          server = start_agent(c)
          id = Server.agent(server).id
          children = monitor_agent_tree(c, server)
          FaultAdapter.arm(c.control, {1, {@stage, self()}})
          signal = Probe.record_and_deliver_signal!("effect", 7)

          caller =
            Task.async(fn ->
              try do
                Server.call(server, signal, timeout: 60_000)
              catch
                :exit, reason -> {:exit, reason}
              end
            end)

          assert_receive {:checkpoint_barrier, @stage, ^server}, 10_000
          revision = if @stage == :before_write, do: 0, else: 1
          assert {:ok, stored, ^revision} = load(c, id)
          assert stored.state.value == if(revision == 0, do: 0, else: 7)
          assert Sink.records(c.jido) == %{}

          # The Server is blocked in its persistence callback; do not call it to
          # obtain child state. Its supervisor owns and removes Plugin workers.
          monitor = Process.monitor(server)
          Observability.killed(c.observer, server)
          Process.exit(server, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 10_000
          await_down(children)
          assert_empty_agent_pool(c)
          assert {:exit, _} = Task.await(caller, 10_000)
          assert Jido.whereis_agent(c.jido, id) == nil
          assert {:ok, ^stored, ^revision} = load(c, id)

          restored = start_agent(c, id: id, restore: :required)
          records = if revision == 0, do: %{}, else: %{"effect" => 7}
          completed(c, restored, records)
          assert Sink.records(c.jido) == records
          assert Server.snapshot(restored).state_version == if(revision == 0, do: 0, else: 2)
          stop_agent(c, restored)
        end
      end

      test "a lost write reply stops admission and restores saved intent", c do
        server = start_agent(c)
        id = Server.agent(server).id
        monitor = Process.monitor(server)
        signal = Probe.record_and_deliver_signal!("effect", 7)
        FaultAdapter.arm(c.control, {1, :lost_reply})

        assert {:error, {:persistence_failed, {:indeterminate, :system_lost_reply}}} =
                 Server.call(server, signal)

        assert_receive {:DOWN, ^monitor, :process, ^server, _}, 10_000
        assert Sink.records(c.jido) == %{}

        assert {:ok, %{state: %{value: 7, delivery: %{pending: %{"effect" => 7}}}}, 1} =
                 load(c, id)

        Observability.assert_turn(c.observer, signal, :error, false)
        Observability.assert_persistence(c.observer, :indeterminate)

        restored = start_agent(c, id: id, restore: :required)
        completed(c, restored, %{"effect" => 7})
        assert Sink.records(c.jido) == %{"effect" => 7}
        stop_agent(c, restored)
      end
    end
  end
end
