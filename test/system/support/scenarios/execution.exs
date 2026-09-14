defmodule JidoTest.System.Scenarios.Execution do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      alias Jido.AgentServer, as: Server
      alias JidoTest.RecoverableDeliveryAgent, as: Probe
      alias JidoTest.RecoverableDeliverySink, as: Sink
      alias JidoTest.System.{ControlledAgent, FaultAdapter, Observability}

      for outcome <- [:cancelled, :timed_out] do
        @execution_outcome outcome
        test "#{@execution_outcome} execution cannot commit a late result across restoration",
             c do
          timeout = if @execution_outcome == :timed_out, do: 100, else: :infinity
          server = start_agent(c, module: ControlledAgent, turn_timeout: timeout)
          id = Server.agent(server).id
          gate = make_ref()
          signal = ControlledAgent.signal(99, gate: gate, observer: self())
          request = Server.send_request(server, signal, :infinity)
          assert_receive {:work_held, ^gate, worker}, 10_000
          monitor = Process.monitor(worker)

          {_, _, _, started} =
            Observability.await(c.observer, fn
              {^server, [:jido, :agent, :turn, :start], _, %{source_signal_id: source}} ->
                source == signal.id

              _ ->
                false
            end)

          turn_id = started.turn_id

          if @execution_outcome == :cancelled do
            assert :ok = Server.cancel_turn(server, turn_id)
            assert {:reply, {:error, :cancelled}} = Server.receive_response(request, 10_000)
          else
            assert {:reply, {:error, %Jido.Error.TimeoutError{} = error}} =
                     Server.receive_response(request, 10_000)

            assert Jido.Error.code(error) == :agent_turn_timeout
          end

          assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 10_000
          assert {:ok, %{state: %{value: 0}}, 0} = load(c, id, ControlledAgent)
          assert {:error, :stale_turn} = Server.cancel_turn(server, turn_id)
          send(server, {make_ref(), {:ok, %{value: 99}}})
          assert Server.agent(server).state == %{value: 0}

          {_, _, _, metadata} =
            Observability.await(c.observer, fn
              {^server, [:jido, :agent, :turn, :stop], _, %{turn_id: ^turn_id}} -> true
              _ -> false
            end)

          assert metadata.status == @execution_outcome
          refute metadata.committed?

          assert {:ok, accepted} = Server.call(server, ControlledAgent.signal(7))
          kill_agent(c, server)
          restored = start_agent(c, module: ControlledAgent, id: id, restore: :required)
          assert Server.snapshot(restored) == %{agent: accepted, state_version: 1}
          assert {:ok, ^accepted, 1} = load(c, id, ControlledAgent)
          assert Sink.attempts(c.jido) == []
          stop_agent(c, restored)
        end
      end

      for stage <- [:before_write, :after_write], request <- [:cancel, :caller_timeout] do
        @commit_stage stage
        @commit_request request
        test "#{@commit_request} at checkpoint #{@commit_stage} cannot reverse a commit", c do
          server = start_agent(c)
          id = Server.agent(server).id
          signal = Probe.record_and_deliver_signal!("committed", 7)
          FaultAdapter.arm(c.control, {1, {@commit_stage, self()}})

          # A caller timeout is real protocol behavior, not a sleep used to
          # guess completion. Hold the checkpoint until that caller has exited.
          timeout = if @commit_request == :caller_timeout, do: 100, else: 10_000

          caller =
            Task.async(fn ->
              try do
                Server.call(server, signal, timeout)
              catch
                :exit, reason -> {:caller_exit, reason}
              end
            end)

          assert_receive {:checkpoint_barrier, @commit_stage, ^server}, 10_000

          {_, _, _, started} =
            Observability.await(c.observer, fn
              {^server, [:jido, :agent, :turn, :start], _, %{source_signal_id: signal_id}} ->
                signal_id == signal.id

              _ ->
                false
            end)

          cancel =
            if @commit_request == :cancel do
              # Queue the same request as cancel_turn/3 without blocking this
              # test. The release below comes from the same sender.
              :gen_statem.send_request(server, {:cancel, started.turn_id})
            else
              assert {:caller_exit, {:timeout, _}} = Task.await(caller, 10_000)
              nil
            end

          send(server, :release_checkpoint)

          if cancel do
            assert {:reply, {:error, :stale_turn}} = Server.receive_response(cancel, 10_000)
            assert {:ok, _} = Task.await(caller, 10_000)
          end

          completed(c, server, %{"committed" => 7})
          snapshot = Server.snapshot(server)
          assert {:ok, stored, 2} = load(c, id)
          assert stored == snapshot.agent
          Observability.assert_turn(c.observer, signal, :ok, true)
          kill_agent(c, server)
          restored = start_agent(c, id: id, restore: :required)
          assert Server.snapshot(restored) == snapshot
          stop_agent(c, restored)
          assert Sink.records(c.jido) == %{"committed" => 7}
          assert length(Sink.attempts(c.jido)) == 1
        end
      end
    end
  end
end
