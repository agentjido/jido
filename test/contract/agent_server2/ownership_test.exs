Code.require_file("support.ex", __DIR__)

defmodule JidoTest.AgentServer2.OwnershipTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server2", async: false

  alias Jido.AgentServer2, as: Server
  alias JidoTest.AgentServer2.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server2.I16"
  test "ownership is recorded before Action or Flow execution can call back during startup", c do
    # A single scheduler makes the high-priority tracer run before the
    # execution Task can consume the Worker reply. Restore the VM setting.
    schedulers = :erlang.system_flag(:schedulers_online, 1)
    on_exit(fn -> :erlang.system_flag(:schedulers_online, schedulers) end)

    for type <- ["work", "flow"] do
      server = F.start(c, max_postponed_signals: 0)
      observer = self()
      # Hold the short execution-admission task after the Worker accepts it.
      # The Action can now run while AgentServer2 is still in startup.
      tracer =
        spawn_link(fn ->
          Process.flag(:priority, :max)
          send(observer, :tracer_ready)
          trace_startup(observer)
        end)

      assert_receive :tracer_ready, 1_000
      :erlang.trace_pattern({Runic.Runner, :start_execution, 4}, true, [:local])
      :erlang.trace(:new, true, [:call, :send, {:tracer, tracer}])

      try do
        pending =
          Server.submit(server, F.signal(%{mode: :probe}, type),
            context: %{server: server, observer: self()}
          )

        assert_receive {:startup_held, task}, 1_000
        assert %{active: %{stage: :starting}} = Server.status(server)
        expected = {List.duplicate({:error, :reentrant_turn}, 4), c.agent.id}
        assert_receive {:probe, ^expected, ^expected}, 1_000
        assert_receive {:executing, _, _, _}, 1_000
        send(tracer, :resume)
        assert_receive {:startup_resumed, ^task}, 1_000
        assert {:ok, %{state: %{count: 1}}, []} = Server.await(pending, 1_000)
        F.clean(c.runner)
      after
        send(tracer, :resume)
        :erlang.trace(:all, false, [:call, :send])
        :erlang.trace(:new, false, [:call, :send])
        :erlang.trace_pattern({Runic.Runner, :start_execution, 4}, false, [:local])
        # Tracer death also releases any process suspension on a failed check.
        Process.unlink(tracer)
        Process.exit(tracer, :kill)
        if Process.alive?(server), do: Server.stop(server)
      end
    end
  end

  @tag obligation: ["jido.agent_server2.I17", "jido.agent_server2.I20", "jido.agent_server2.I21"]
  test "successful candidate cannot commit after its deadline expires during cleanup", c do
    server = F.start(c, turn_timeout: 200)
    turn = F.blocked(server, c.runner)
    supervisor = Module.concat(c.runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)

    try do
      F.release(turn)
      assert_eventually(Server.status(server).active.stage == :cleaning)
      F.elapsed(220)
      assert Server.agent(server) === c.agent
      assert {:error, :timeout} = Server.await(turn.pending, 0)
      :ok = :sys.resume(supervisor)
      assert {:error, :turn_timeout} = Server.await(turn.pending, 1_000)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
    after
      :sys.resume(supervisor)
    end
  end

  @tag obligation: "jido.agent_server2.I17"
  test "delayed timer cannot permit commit when cleanup result was queued first", c do
    server = F.start(c, turn_timeout: 200)
    turn = F.blocked(server, c.runner)
    supervisor = Module.concat(c.runner, WorkerSupervisor)
    :ok = :sys.suspend(supervisor)

    try do
      F.release(turn)
      assert_eventually(Server.status(server).active.stage == :cleaning)
      # State access controls a private scheduling boundary; it does not make
      # this task record part of the public API.
      {_phase, data} = :sys.get_state(server)
      cleanup = data.active.operation.task
      :ok = :sys.suspend(server)
      :ok = :sys.resume(supervisor)
      F.down(cleanup.pid)
      F.elapsed(220)
      {:messages, messages} = Process.info(server, :messages)
      result_index = Enum.find_index(messages, &match?({ref, :ok} when ref == cleanup.ref, &1))
      timer_index = Enum.find_index(messages, &(&1 == {:turn_timeout, turn.id}))
      assert is_integer(result_index) and is_integer(timer_index)
      assert result_index < timer_index
      :ok = :sys.resume(server)
      assert {:error, :turn_timeout} = Server.await(turn.pending, 1_000)
      F.unchanged(server, c.agent)
      F.clean(c.runner)
    after
      :sys.resume(supervisor)
      if Process.alive?(server), do: :sys.resume(server)
    end
  end

  defp trace_startup(observer, task \\ nil) do
    receive do
      {:trace, pid, :call, {Runic.Runner, :start_execution, _}} ->
        trace_startup(observer, pid)

      {:trace, _sender, :send, {_tag, {:ok, %Runic.Identity{domain: :execution}}}, _dest}
      when is_pid(task) ->
        true = :erlang.suspend_process(task)
        send(observer, {:startup_held, task})

        receive do
          :resume ->
            true = :erlang.resume_process(task)
            send(observer, {:startup_resumed, task})
        end

      _ ->
        trace_startup(observer, task)
    end
  end
end
