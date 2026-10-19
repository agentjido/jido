defmodule JidoTest.AgentServer.DurableTurnTest do
  use JidoTest.Case, async: false
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias JidoTest.DurableFixtures, as: F

  setup do
    start_supervised!({F.Probe, self()})
    :ok
  end

  defp start(c, opts \\ []) do
    {:ok, server} =
      Jido.start_agent(
        c.jido,
        F.Worker,
        Keyword.merge(
          [
            id: unique_id("durable"),
            persistence: {Jido.Persistence.File, path: c.tmp_dir}
          ],
          opts
        )
      )

    assert :ok = Server.await_ready(server)
    server
  end

  defp replacement(c, id, old) do
    server =
      eventually(fn ->
        case Jido.whereis_agent(c.jido, id) do
          pid when is_pid(pid) and pid != old -> pid
          _ -> nil
        end
      end)

    assert :ok = Server.await_ready(server)
    server
  end

  test "a 90-day saved deadline survives AgentServer loss", c do
    duration = 90 * 24 * 60 * 60 * 1_000
    server = start(c, turn_timeout: duration)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, action}, 5_000
    {_, %{active: before}} = :sys.get_state(server)
    monitor = Process.monitor(server)
    action_monitor = Process.monitor(action)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000
    assert_receive {:DOWN, ^action_monitor, :process, ^action, _}, 5_000
    restored = replacement(c, id, server)
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    {_, %{active: after_restore}} = :sys.get_state(restored)
    assert after_restore.turn_id == before.turn_id
    assert_in_delta after_restore.deadline, before.deadline, 1_000
    assert Process.read_timer(after_restore.timer) <= 4_294_967_295
    assert F.Probe.records() == Enum.to_list(1..6) ++ [6]
    F.Probe.release()
    assert :ok = Server.quiesce(restored)
    assert Server.agent(restored).state == %{count: 10}
    assert Server.status(restored).durable_turn == %{id: before.turn_id, status: :completed}
    assert F.Probe.records() == Enum.to_list(1..6) ++ Enum.to_list(6..10)
    assert {:error, _} = Server.await(pending)
  end

  for victim <- [:server, :activation, :worker] do
    test "#{victim} loss resumes the current Turn at step 6", c do
      server = start(c)
      id = Server.agent(server).id
      pending = Server.submit(server, signal("request", %{value: 0}))
      assert_receive {:durable_barrier, :step_6, action}, 5_000
      turn_id = Server.status(server).active.turn_id

      target =
        case unquote(victim) do
          :server ->
            server

          :activation ->
            Server.activation(server)

          :worker ->
            Runic.Runner.lookup(
              Jido.exec_runner_name(c.jido),
              Jido.AgentServer.CheckpointStore.identity(
                %{jido: c.jido, partition: nil, agent_id: id},
                turn_id
              )
            )
        end

      monitor = Process.monitor(target)
      action_monitor = Process.monitor(action)
      Process.exit(target, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^target, :killed}, 5_000
      assert_receive {:DOWN, ^action_monitor, :process, ^action, _}, 5_000
      restored = replacement(c, id, server)
      assert_receive {:durable_barrier, :step_6, _}, 5_000
      assert Server.status(restored).active.turn_id == turn_id
      assert Server.agent(restored).state == %{count: 0}
      assert F.Probe.records() == Enum.to_list(1..6) ++ [6]
      F.Probe.release()
      eventually(fn -> Server.agent(restored).state == %{count: 10} end)
      assert Server.status(restored).durable_turn == %{id: turn_id, status: :completed}
      assert F.Probe.records() == Enum.to_list(1..6) ++ Enum.to_list(6..10)
      assert {:error, _} = Server.await(pending)
      assert :ok = Server.hibernate(restored)

      assert {:ok, awake} =
               Jido.thaw(c.jido, F.Worker, id,
                 persistence: {Jido.Persistence.File, path: c.tmp_dir}
               )

      assert :ok = Server.await_ready(awake)
      assert Server.agent(awake).state == %{count: 10}
      assert F.Probe.records() == Enum.to_list(1..6) ++ Enum.to_list(6..10)
    end
  end

  test "a Flow holds the Turn while reads and cancellation stay available", c do
    server = start(c)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, action}, 5_000
    turn_id = Server.status(server).active.turn_id
    queued = Server.submit(server, signal("increment"))
    eventually(fn -> Server.status(server).admission.postponed == 1 end)
    assert Server.agent(server).state == %{count: 0}
    monitor = Process.monitor(action)
    assert :ok = Server.cancel_turn(server, turn_id)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000
    assert {:error, _} = Server.await(pending)
    assert {:ok, agent, []} = Server.await(queued)
    assert agent.state == %{count: 1}
    assert Server.status(server).durable_turn.status == :cancelled
    assert :ok = Server.hibernate(server)

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id,
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored).state == %{count: 1}
    assert F.Probe.records() == Enum.to_list(1..6)
  end

  test "successful Flow commits once before the next Turn", c do
    server = start(c)
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    queued = Server.submit(server, signal("increment"))
    F.Probe.release()
    assert {:ok, agent, []} = Server.await(pending)
    assert agent.state == %{count: 10}
    assert {:ok, agent, []} = Server.await(queued)
    assert agent.state == %{count: 11}
  end

  test "nonportable command context is rejected before execution", c do
    server = start(c)

    assert {:error, _} =
             Server.call(server, signal("request", %{value: 0}), context: %{pid: self()})

    assert F.Probe.records() == []
    assert Server.agent(server).state == %{count: 0}
  end

  test "a rejected acceptance save starts no Action", c do
    server = start(c, persistence: {F.Reject, path: c.tmp_dir})
    assert {:error, _} = Server.call(server, signal("request", %{value: 0}))
    assert F.Probe.records() == []
  end

  for boundary <- [:intent_write, :input_write] do
    test "recovery resolves the saved #{boundary} before the reply", c do
      server = start(c, persistence: {F.Storage, path: c.tmp_dir})
      id = Server.agent(server).id
      F.Probe.configure(unquote(boundary))
      pending = Server.submit(server, signal("request", %{value: 0}))
      assert_receive {:durable_barrier, unquote(boundary), _}, 5_000
      turn_id = Server.status(server).active.turn_id
      monitor = Process.monitor(server)
      Process.exit(server, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 5_000
      F.Probe.release()
      restored = replacement(c, id, server)
      assert_receive {:durable_barrier, :step_6, _}, 5_000
      assert Server.status(restored).active.turn_id == turn_id
      F.Probe.release()
      eventually(fn -> Server.agent(restored).state.count == 10 end)
      assert F.Probe.records() == Enum.to_list(1..10)
      assert {:error, _} = Server.await(pending)
    end
  end

  test "a rejected step checkpoint cannot dispatch the next Action", c do
    server = start(c, persistence: {F.Storage, path: c.tmp_dir})
    id = Server.agent(server).id
    activation = Server.activation(server)
    monitor = Process.monitor(activation)
    F.Probe.configure(:reject_checkpoint)
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert {:error, _} = Server.await(pending)
    assert F.Probe.records() == Enum.to_list(1..5)

    # The failed Turn replies before the activation has fully stopped.
    # Confirm shutdown before starting another server with the same identity.
    assert_receive {:DOWN, ^monitor, :process, ^activation, :shutdown}, 5_000

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id, persistence: {F.Storage, path: c.tmp_dir})

    assert :ok = Server.await_ready(restored)
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    assert F.Probe.records() == Enum.to_list(1..5) ++ [5, 6]
    F.Probe.release()
    eventually(fn -> Server.agent(restored).state.count == 10 end)
  end

  test "a stored completion is recovered after the commit reply is lost", c do
    server = start(c, persistence: {F.Storage, path: c.tmp_dir})
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    F.Probe.configure(:completion_write)
    F.Probe.release()
    assert_receive {:durable_barrier, :completion_write, _}, 5_000
    turn_id = Server.status(server).active.turn_id
    Process.exit(server, :kill)
    F.Probe.release()
    restored = replacement(c, id, server)
    assert Server.agent(restored).state == %{count: 10}
    assert Server.status(restored).durable_turn == %{id: turn_id, status: :completed}
    assert F.Probe.records() == Enum.to_list(1..10)
    assert {:error, _} = Server.await(pending)
  end

  test "corrupt graph data fails recovery instead of starting a new Flow", c do
    server = start(c)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    assert :ok = Server.stop(server)
    assert {:error, _} = Server.await(pending)

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id, persistence: {F.Corrupt, path: c.tmp_dir})

    monitor = Process.monitor(restored)
    assert_receive {:DOWN, ^monitor, :process, ^restored, _}, 5_000
    assert F.Probe.records() == Enum.to_list(1..6)
  end

  defp update_receipt(c, id, fun) do
    key =
      Jido.Persistence.agent_key(Jido.Agent.Ref.new!(namespace: Jido.namespace(c.jido), id: id))

    opts = [path: c.tmp_dir]
    assert {:ok, bytes} = Jido.Persistence.File.get(key, opts)
    record = :erlang.binary_to_term(bytes, [:safe])
    changed = %{record | server_turn: fun.(record.server_turn)}

    assert :ok =
             Jido.Persistence.File.compare_and_swap(
               key,
               bytes,
               :erlang.term_to_binary(changed),
               opts
             )
  end

  test "changed Flow code fails readiness without dispatch", c do
    server = start(c)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    assert :ok = Server.stop(server)
    assert {:error, _} = Server.await(pending)
    update_receipt(c, id, &%{&1 | fingerprint: "changed-code"})

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id,
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert {{:shutdown, :execution_definition_changed}, _} =
             catch_exit(Server.await_ready(restored))

    assert F.Probe.records() == Enum.to_list(1..6)
  end

  test "an expired saved Turn does not receive a new timeout budget", c do
    server = start(c)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    assert :ok = Server.stop(server)
    assert {:error, _} = Server.await(pending)
    update_receipt(c, id, &%{&1 | expires_at: 0})

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id,
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert :ok = Server.await_ready(restored)
    eventually(fn -> Server.status(restored).durable_turn.status == :failed end)
    assert Server.agent(restored).state == %{count: 0}
    assert F.Probe.records() == Enum.to_list(1..6)
  end

  for route <- ["bad_output", "effects"] do
    test "#{route} failure saves a terminal Turn without changing Agent state", c do
      server = start(c)
      id = Server.agent(server).id
      assert {:error, _} = Server.call(server, signal(unquote(route)))
      assert Server.status(server).durable_turn.status == :failed
      assert Server.agent(server).state == %{count: 0}
      assert :ok = Server.hibernate(server)

      assert {:ok, restored} =
               Jido.thaw(c.jido, F.Worker, id,
                 persistence: {Jido.Persistence.File, path: c.tmp_dir}
               )

      assert :ok = Server.await_ready(restored)
      assert Server.status(restored).durable_turn.status == :failed
      assert Server.agent(restored).state == %{count: 0}
    end
  end

  test "cancellation during Worker startup closes its scope before the next Turn", c do
    server = start(c, persistence: {F.Storage, path: c.tmp_dir})
    id = Server.agent(server).id
    F.Probe.configure(:input_write)
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :input_write, _}, 5_000
    turn_id = Server.status(server).active.turn_id

    identity =
      Jido.AgentServer.CheckpointStore.identity(
        %{jido: c.jido, partition: nil, agent_id: id},
        turn_id
      )

    worker = Runic.Runner.lookup(Jido.exec_runner_name(c.jido), identity)
    assert is_pid(worker)
    monitor = Process.monitor(worker)
    assert :ok = Server.cancel(server)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 5_000
    assert {:error, _} = Server.await(pending)
    assert Runic.Runner.lookup(Jido.exec_runner_name(c.jido), identity) == nil
    assert F.Probe.records() == []
    assert Server.status(server).durable_turn.status == :cancelled
    assert {:ok, agent, []} = Server.call(server, signal("increment"))
    assert agent.state == %{count: 1}
  end

  test "a saved completion does not replay post-commit hooks", c do
    agent = F.Worker.instantiate!(id: unique_id("hooked"))

    {:ok, agent} =
      Jido.Agent.Composition.apply(agent, agent.state, [Jido.Agent.Directive.plugin_add(F.Hook)])

    {:ok, server} =
      Jido.start_agent(c.jido, agent, persistence: {Jido.Persistence.File, path: c.tmp_dir})

    assert :ok = Server.await_ready(server)
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, _}, 5_000
    F.Probe.configure(:hook_gate)
    F.Probe.release()
    assert_receive {:durable_barrier, :hook, _}, 5_000
    Process.exit(server, :kill)
    F.Probe.release()
    restored = replacement(c, agent.id, server)
    assert Server.agent(restored).state == %{count: 10}
    assert Server.status(restored).durable_turn.status == :completed
    assert F.Probe.hook_count() == 1
    assert F.Probe.records() == Enum.to_list(1..10)
    # Commit acknowledgement precedes post-commit hooks in the existing contract.
    assert {:ok, _, []} = Server.await(pending)
  end

  test "Flow mutation Directives commit with state and restore without reapplying", c do
    server = start(c)
    id = Server.agent(server).id
    assert {:ok, agent, [_]} = Server.call(server, signal("topology"))
    assert :ok = Server.await_ready(server)
    assert agent.state == %{count: 1}
    assert [nested] = Server.members(server, :nested)
    nested_id = Server.agent(nested).id
    assert {:ok, snapshot} = Jido.Persistence.snapshot(Server.agent(server))
    assert :ok = Server.hibernate(server)

    assert {:ok, restored} =
             Jido.thaw(c.jido, F.Worker, id,
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert :ok = Server.await_ready(restored)
    assert {:ok, ^snapshot} = Jido.Persistence.snapshot(Server.agent(restored))
    assert [child] = Server.members(restored, :nested)
    assert Server.agent(child).id == nested_id
    assert Server.status(restored).durable_turn.status == :completed
  end

  test "without persistence an interrupted Flow is not restored", c do
    server = start(c, persistence: false)
    id = Server.agent(server).id
    pending = Server.submit(server, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, action}, 5_000
    action_monitor = Process.monitor(action)
    server_monitor = Process.monitor(server)
    assert Server.status(server).durable_turn == nil

    Process.exit(server, :kill)
    assert_receive {:DOWN, ^server_monitor, :process, ^server, :killed}, 5_000
    assert_receive {:DOWN, ^action_monitor, :process, ^action, _}, 5_000
    restored = replacement(c, id, server)
    assert Server.status(restored).active == nil
    assert Server.status(restored).durable_turn == nil
    assert Server.agent(restored).state == %{count: 0}
    assert F.Probe.records() == Enum.to_list(1..6)
    assert {:error, _} = Server.await(pending)
  end
end
