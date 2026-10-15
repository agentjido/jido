defmodule Jido.AgentServer.StartedExecutionTest do
  use JidoTest.Case, async: true
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServerRuntimeFixtures.OwnedExecutionAgent

  test "finished Turns release Workers, tasks, and Store data", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent)
    runner = Jido.exec_runner_name(jido)
    {store, store_state} = Runic.Runner.get_store(runner)

    for _ <- 1..20 do
      gate = make_ref()

      request =
        Server.send_request(
          server,
          signal("owned.action", %{test: self(), gate: gate, label: :release})
        )

      assert_receive {:owned_execution, :release, worker}, 2_000
      ref = Process.monitor(worker)
      send(worker, {:release, gate})
      assert {:reply, {:ok, _}} = Server.receive_response(request, 2_000)
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 2_000
      assert DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor)) == []
      assert {:ok, []} = store.list(store_state)
      assert :ets.info(store_state.events_table, :size) == 0
      assert :ets.info(store_state.facts_table, :size) == 0
    end

    assert Task.Supervisor.children(Module.concat(runner, TaskSupervisor)) == []
    assert Server.status(server).state_version == 20
  end

  test "cancellation during start waits for owned cleanup", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent, turn_timeout: :infinity)
    runner = Jido.exec_runner_name(jido)
    supervisor = Module.concat(runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)
    on_exit(fn -> if Process.whereis(supervisor), do: :sys.resume(supervisor) end)

    :ok =
      Server.cast(
        server,
        signal("owned.action", %{test: self(), gate: make_ref(), label: :start})
      )

    assert {:starting, state} = :sys.get_state(server)
    request = :gen_statem.send_request(server, {:cancel, state.active.turn_id})
    assert {:cancelling, _} = :sys.get_state(server)
    assert Server.status(server).state_version == 0
    :ok = :sys.resume(supervisor)
    assert {:reply, :ok} = :gen_statem.receive_response(request, 2_000)
    assert DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor)) == []
    assert Server.status(server).phase == :idle
  end

  test "cancellation during settlement prevents commit", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent, turn_timeout: :infinity)
    runner = Jido.exec_runner_name(jido)
    gate = make_ref()

    request =
      Server.send_request(
        server,
        signal("owned.action", %{test: self(), gate: gate, label: :settle})
      )

    assert_receive {:owned_execution, :settle, action}, 2_000
    eventually(fn -> elem(:sys.get_state(server), 0) == :running end)
    {:running, state} = :sys.get_state(server)
    worker_ref = Process.monitor(state.active.exec_handle.pid)
    supervisor = Module.concat(runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)
    on_exit(fn -> if Process.whereis(supervisor), do: :sys.resume(supervisor) end)
    send(action, {:release, gate})
    assert_receive {:DOWN, ^worker_ref, :process, _, _}, 2_000
    assert {:settling, _} = :sys.get_state(server)
    cancel = :gen_statem.send_request(server, {:cancel, state.active.turn_id})
    assert {:cancelling, _} = :sys.get_state(server)
    :ok = :sys.resume(supervisor)
    assert {:reply, :ok} = :gen_statem.receive_response(cancel, 2_000)
    assert {:reply, {:error, :cancelled}} = Server.receive_response(request, 2_000)
    assert Server.status(server).state_version == 0
  end

  test "parent death during cancellation still stops the child", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, OwnedExecutionAgent, restart: :temporary)
    parent_ref = Server.ParentRef.new!(pid: parent, id: Server.agent(parent).id, tag: :owner)

    {:ok, child} =
      Jido.start_agent(jido, OwnedExecutionAgent,
        parent: parent_ref,
        on_parent_death: :stop,
        restart: :temporary,
        turn_timeout: :infinity
      )

    supervisor = Module.concat(Jido.exec_runner_name(jido), WorkerSupervisor)
    :ok = :sys.suspend(supervisor)
    on_exit(fn -> if Process.whereis(supervisor), do: :sys.resume(supervisor) end)

    :ok =
      Server.cast(
        child,
        signal("owned.action", %{test: self(), gate: make_ref(), label: :parent})
      )

    {:starting, state} = :sys.get_state(child)
    request = :gen_statem.send_request(child, {:cancel, state.active.turn_id})
    assert {:cancelling, _} = :sys.get_state(child)
    child_ref = Process.monitor(child)
    :ok = Jido.stop_agent(jido, parent)
    eventually(fn -> is_nil(elem(:sys.get_state(child), 1).parent) end)
    :ok = :sys.resume(supervisor)
    assert {:reply, :ok} = :gen_statem.receive_response(request, 2_000)
    assert_receive {:DOWN, ^child_ref, :process, ^child, {:shutdown, {:parent_down, _}}}, 2_000
  end

  test "a full lifecycle task pool rejects the Turn without stopping the Server", %{jido: base} do
    jido = Module.concat(base, Limited)
    start_supervised!({Jido, name: jido, max_tasks: 1}, id: jido)
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent)

    {:ok, blocker} =
      Task.Supervisor.start_child(Jido.task_supervisor_name(jido), fn ->
        receive do: (:release -> :ok)
      end)

    ref = Process.monitor(blocker)
    command = signal("owned.action", %{test: self(), gate: make_ref(), label: :capacity})
    assert {:error, %Jido.Error.ExecutionError{}} = Server.call(server, command)
    assert Server.status(server).state_version == 0
    send(blocker, :release)
    assert_receive {:DOWN, ^ref, :process, ^blocker, :normal}, 2_000
    gate = make_ref()

    request =
      Server.send_request(
        server,
        signal("owned.action", %{test: self(), gate: gate, label: :capacity})
      )

    assert_receive {:owned_execution, :capacity, action}, 2_000
    send(action, {:release, gate})
    assert {:reply, {:ok, _}} = Server.receive_response(request, 2_000)
    assert Server.status(server).state_version == 1
  end
end
