defmodule Jido.AgentServer.StartedExecutionTest do
  use JidoTest.Case, async: true
  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentServerRuntimeFixtures.OwnedExecutionAgent

  defmodule LocalValueAction do
    use Jido.Action, name: "local_execution_values"

    @impl true
    def run(%{payload: value}, %{local_context: context}) do
      {:ok, %{payload: value, context: context}}
    end
  end

  defmodule LocalValueFlow do
    use Jido.Flow, name: "local_execution_values_flow"

    flow do
      step "local", action: LocalValueAction, params: input()
      output result("local")
    end
  end

  defmodule RetryAction do
    use Jido.Action, name: "local_execution_retry"

    @impl true
    def run(_params, context) do
      if :atomics.add_get(context.attempts, 1, 1) == 1 do
        {:error, Jido.Action.Error.execution_error("attempt failed", %{retry: context.retry?})}
      else
        {:ok, context.agent_state}
      end
    end
  end

  test "Action and Flow Turns accept local input, context, and output values", %{jido: jido} do
    definition =
      Jido.Agent.new!(
        name: "local_execution",
        schema: Zoi.object(%{payload: Zoi.any(), context: Zoi.any()}),
        routes: [{"local.action", LocalValueAction}, {"local.flow", LocalValueFlow}]
      )

    agent = Jido.Agent.instantiate!(definition, state: %{payload: nil, context: nil})
    {:ok, server} = Jido.start_agent(jido, agent)
    port = Port.open({:spawn_executable, System.find_executable("true")}, [])
    on_exit(fn -> if Port.info(port), do: Port.close(port) end)

    values = [self(), make_ref(), fn -> :local end, port, [1 | :tail], <<5::size(3)>>]

    for type <- ["local.action", "local.flow"], value <- values do
      context = %{observer: self(), reference: make_ref(), callback: fn -> value end}

      assert {:ok, candidate} =
               Server.call(server, signal(type, %{payload: value}),
                 context: %{local_context: context}
               )

      assert candidate.state.payload === value
      assert candidate.state.context === context
      assert Server.snapshot(server).agent == candidate
    end

    assert Server.status(server).state_version == 12
  end

  test "local execution retries only errors that permit a retry", %{jido: jido} do
    definition =
      Jido.Agent.new!(name: "local_retry", routes: [{"retry", RetryAction}])

    for {retry?, opts, expected_attempts} <- [
          {true, [max_attempts: 2, backoff: :linear, base_delay_ms: 1, max_delay_ms: 1], 2},
          {false, [max_attempts: 2], 1},
          {true, [], 1}
        ] do
      agent = Jido.Agent.instantiate!(definition)
      {:ok, server} = Jido.start_agent(jido, agent, exec_opts: opts)
      attempts = :atomics.new(1, [])

      result =
        Server.call(server, signal("retry"), context: %{attempts: attempts, retry?: retry?})

      if expected_attempts == 2 do
        assert {:ok, _candidate} = result
        assert Server.status(server).state_version == 1
      else
        assert {:error, %Jido.Action.Error.ExecutionFailureError{}} = result
        assert Server.status(server).state_version == 0
      end

      assert :atomics.get(attempts, 1) == expected_attempts
    end
  end

  test "invalid local execution options fail before dispatch and preserve the Server", %{
    jido: jido
  } do
    for opts <- [
          [max_attempts: 0],
          [max_concurrency: 0],
          [timeout: -1],
          [backoff: :invalid],
          [base_delay_ms: -1],
          [max_delay_ms: -1],
          [unknown_option: true]
        ] do
      {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent, exec_opts: opts)
      initial = Server.snapshot(server)
      command = signal("owned.action", %{test: self(), gate: make_ref(), label: :invalid})

      assert {:error, %Jido.Action.Error.ConfigurationError{}} = Server.call(server, command)
      assert Server.status(server).phase == :idle
      assert Server.snapshot(server) == initial

      assert DynamicSupervisor.which_children(
               Module.concat(Jido.exec_runner_name(jido), WorkerSupervisor)
             ) == []

      refute_received {:owned_execution, :invalid, _worker}
    end
  end

  test "a caller failure hook receives the original execution error", %{jido: jido} do
    test = self()
    hook = fn _runnable, error, _state -> send(test, {:local_failure, error}) end
    definition = Jido.Agent.new!(name: "local_hook", routes: [{"retry", RetryAction}])

    {:ok, server} =
      Jido.start_agent(jido, Jido.Agent.instantiate!(definition),
        exec_opts: [hooks: [on_failed: hook]]
      )

    assert {:error, error} =
             Server.call(server, signal("retry"),
               context: %{attempts: :atomics.new(1, []), retry?: false}
             )

    assert_receive {:local_failure, ^error}
    assert Server.status(server).phase == :idle
    assert Server.status(server).state_version == 0
  end

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
      turn_id = Server.status(server).active.turn_id
      ref = Process.monitor(worker)
      send(worker, {:release, gate})
      assert {:reply, {:ok, _}} = Server.receive_response(request, 2_000)
      assert_receive {:DOWN, ^ref, :process, ^worker, _}, 2_000
      assert DynamicSupervisor.which_children(Module.concat(runner, WorkerSupervisor)) == []
      assert {:ok, []} = store.list(store_state)
      assert {:error, :not_found} = store.load(turn_id, store_state)
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
