defmodule JidoTest.System.Scenarios.Effects do
  @moduledoc false
  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.AgentServer, as: Server
      alias JidoTest.RecoverableDeliveryAgent, as: Probe
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.{FaultAdapter, Observability}

      for stage <- [:before_write, :after_write] do
        @stage stage
        test "Agent crash at effect #{@stage} replays intent without duplicate sink records", c do
          :ok = Sink.hold(c.jido, @stage)
          server = start_agent(c)
          signal = Probe.record_and_deliver_signal!("effect", 7)
          assert {:ok, saved} = Server.call(server, signal)
          assert_receive {:effect_attempt, "effect", task}, 10_000
          records = if @stage == :after_write, do: %{"effect" => 7}, else: %{}
          assert_receive {:effect_barrier, @stage, "effect", ^task}, 10_000
          assert Sink.records(c.jido) == records
          assert {:ok, ^saved, 1} = load(c, saved.id)
          Observability.assert_turn(c.observer, signal, :ok, true)
          task_monitor = Process.monitor(task)
          kill_agent(c, server)
          assert_receive {:DOWN, ^task_monitor, :process, ^task, _}, 10_000
          assert Jido.whereis_agent(c.jido, saved.id) == nil
          :ok = Sink.hold(c.jido, :none)

          restored = start_agent(c, id: saved.id, restore: :required)
          assert_receive {:effect_attempt, "effect", retry_task}, 10_000
          assert retry_task != task
          completed(c, restored, %{"effect" => 7})
          assert %{agent: acknowledged, state_version: 2} = Server.snapshot(restored)
          assert acknowledged.state.value == 7
          assert {:ok, ^acknowledged, 2} = load(c, saved.id)
          stop_agent(c, restored)
          assert Sink.records(c.jido) == %{"effect" => 7}
        end
      end

      test "failed confirmation retains durable intent after an external effect", c do
        :ok = Sink.hold(c.jido, :after_write)
        server = start_agent(c)
        FaultAdapter.arm(c.control, {2, :reject})
        assert {:ok, saved} = Probe.record_and_deliver(server, "effect", 7)
        assert_receive {:effect_attempt, "effect", task}, 10_000
        assert_receive {:effect_barrier, :after_write, "effect", ^task}, 10_000
        assert Sink.records(c.jido) == %{"effect" => 7}
        monitor = Process.monitor(server)
        :ok = Sink.hold(c.jido, :none)
        send(task, :release)
        assert_receive {:DOWN, ^monitor, :process, ^server, _}, 10_000
        assert {:ok, ^saved, 1} = load(c, saved.id)
        Observability.assert_persistence(c.observer, :rejected)
        restored = start_agent(c, id: saved.id, restore: :required)
        completed(c, restored, %{"effect" => 7})
        assert Server.snapshot(restored).state_version == 2
        stop_agent(c, restored)
        assert Sink.records(c.jido) == %{"effect" => 7}
      end
    end
  end
end
