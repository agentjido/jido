defmodule JidoTest.System.Scenarios.Recovery do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Jido.AgentServer, as: Server
      alias JidoTest.RecoverableDeliveryAgent, as: Probe
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.{FaultAdapter, Observability}

      test "two failed recoveries retain intent and record every repeated effect attempt", c do
        :ok = Sink.hold(c.jido, :after_write)
        server = start_agent(c)
        assert {:ok, saved} = Probe.record_and_deliver(server, "stable-effect", 7)
        assert_receive {:effect_attempt, "stable-effect", first}, 10_000
        assert_receive {:effect_barrier, :after_write, "stable-effect", ^first}, 10_000
        assert Sink.records(c.jido) == %{"stable-effect" => 7}

        # The effect is complete, but the activation dies before its reply.
        kill_agent(c, server)
        :ok = FaultAdapter.sequence(c.control, [{2, :reject}, {2, :reject}])

        for _ <- 1..2 do
          restored = start_agent(c, id: saved.id, restore: :required)
          assert_receive {:effect_attempt, "stable-effect", worker}, 10_000
          assert_receive {:effect_barrier, :after_write, "stable-effect", ^worker}, 10_000
          monitors = monitor_agent_tree(c, restored)
          send(worker, :release)
          await_down(monitors)
          assert {:ok, ^saved, 1} = load(c, saved.id)
          assert Sink.records(c.jido) == %{"stable-effect" => 7}
        end

        assert FaultAdapter.remaining(c.control) == []
        :ok = Sink.hold(c.jido, :none)
        final = start_agent(c, id: saved.id, restore: :required)
        completed(c, final, %{"stable-effect" => 7})
        assert %{agent: acknowledged, state_version: 2} = Server.snapshot(final)
        assert {:ok, ^acknowledged, 2} = load(c, saved.id)
        stop_agent(c, final)
        attempts = Sink.attempts(c.jido)
        assert Enum.map(attempts, & &1.effect_id) == List.duplicate("stable-effect", 4)
        assert length(Enum.uniq_by(attempts, & &1.worker)) == 4
        Observability.assert_persistence(c.observer, :rejected)
      end

      for boundary <- [:replacement, :deletion] do
        @late_boundary boundary
        test "a storage request from an old activation is fenced after #{@late_boundary}", c do
          server = start_agent(c)
          assert {:ok, _} = Probe.record_and_deliver(server, "original", 7)
          completed(c, server, %{"original" => 7})
          original = Server.agent(server)
          stale = %{original | state: %{original.state | value: 99}}
          owner = self()

          writer =
            Task.async(fn ->
              send(owner, {:old_write_held, self()})
              receive do: (:release_old_write -> :ok)

              Jido.Persistence.save_agent(c.store, stale,
                instance: c.jido,
                namespace: c.namespace,
                expected_revision: 2,
                revision: 3
              )
            end)

          assert_receive {:old_write_held, old_writer}, 10_000
          kill_agent(c, server)

          replacement =
            if @late_boundary == :replacement do
              current = start_agent(c, id: original.id, restore: :required)
              assert {:ok, _} = Probe.record_and_deliver(current, "new", 9)
              Observability.await_turn(c.observer, current, 4)
              assert Server.agent(current).state.value == 9
              current
            else
              assert :ok =
                       Jido.Persistence.delete_agent(c.store, Probe, original.id,
                         instance: c.jido,
                         namespace: c.namespace
                       )

              assert {:error, :deleted} =
                       Jido.start_agent(c.jido, Probe,
                         id: original.id,
                         persistence: c.store,
                         restore: :required
                       )

              nil
            end

          before_release = load(c, original.id)
          send(old_writer, :release_old_write)
          assert {:error, :conflict} = Task.await(writer, 10_000)
          assert load(c, original.id) == before_release
          expected = if replacement, do: %{"original" => 7, "new" => 9}, else: %{"original" => 7}
          assert Sink.records(c.jido) == expected
          assert length(Sink.attempts(c.jido)) == map_size(expected)
          if replacement, do: stop_agent(c, replacement)
          Observability.assert_persistence(c.observer, :conflict)
        end
      end
    end
  end
end
