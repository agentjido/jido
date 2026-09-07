defmodule Jido.AgentServer.RuntimeLifecycleTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Scheduler

  alias JidoTest.AgentRuntimeFixtures.{
    BootPlugin,
    PluginRuntimeAgent,
    RuntimeAgent
  }

  alias JidoTest.AgentServerRuntimeFixtures.{
    FreshRuntimeAgent,
    FreshRuntimePlugin,
    GenerationAgent,
    ObservedExec,
    OwnedExecutionAgent,
    ReadinessAgent
  }

  defp eventually_agent(server, predicate, timeout \\ 3_000) do
    eventually(
      fn ->
        agent = Server.agent(server)
        if predicate.(agent), do: agent
      end,
      timeout: timeout
    )
  end

  test "Jido instance APIs start, find, list, and stop Agents", %{jido: jido} do
    id = unique_id("agent")
    assert {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)
    assert Jido.whereis_agent(jido, id) == pid
    assert {id, pid} in Jido.list_agents(jido)
    assert Jido.agent_count(jido) == 1
    assert :ok = Jido.stop_agent(jido, id)
    eventually(fn -> Jido.whereis_agent(jido, id) == nil end)
  end

  test "owns Action and Flow execution under the Agent Jido instance", %{jido: jido} do
    {:ok, agent} =
      Jido.start_agent(jido, OwnedExecutionAgent, id: unique_id("owned-execution"))

    task_supervisor = Process.whereis(Jido.task_supervisor_name(jido))
    assert is_pid(task_supervisor)
    test = self()

    for {type, label} <- [{"owned.action", :action}, {"owned.flow", :flow}] do
      gate = make_ref()

      caller =
        Task.async(fn ->
          Server.call(agent, signal(type, %{test: test, gate: gate, label: label}))
        end)

      assert_receive {:owned_execution, ^label, action_worker}, 2_000
      assert action_worker in Task.Supervisor.children(task_supervisor)

      {:running, state} = :sys.get_state(agent)
      exec_root = state.active.exec_handle.pid
      assert exec_root in Task.Supervisor.children(task_supervisor)
      assert agent in elem(Process.info(exec_root, :links), 1)

      send(action_worker, {:release, gate})
      assert {:ok, _agent} = Task.await(caller, 2_000)
    end
  end

  test "Exec receives general messages and unowned DOWN events after attachment handling", %{
    jido: jido
  } do
    {:ok, server} = Jido.start_agent(jido, OwnedExecutionAgent, exec_module: ObservedExec)
    owner = start_supervised!({Elixir.Agent, fn -> nil end})
    assert :ok = Server.attach(server, owner)
    gate = make_ref()
    test = self()

    caller =
      Task.async(fn ->
        Server.call(server, signal("owned.action", %{test: test, gate: gate, label: :routing}))
      end)

    assert_receive {:owned_execution, :routing, worker}, 2_000
    {:running, state} = :sys.get_state(server)
    owner_ref = Map.fetch!(state.attachments, owner)
    Elixir.Agent.stop(owner)
    eventually(fn -> Server.status(server).runtime.lifecycle.attached == 0 end)
    refute_received {:exec_message, {:DOWN, ^owner_ref, :process, ^owner, _}}

    unknown = make_ref()
    down = {:DOWN, unknown, :process, owner, :normal}
    send(server, down)
    send(server, {:exec_probe, gate})
    assert Server.status(server).phase == :running
    assert_receive {:exec_message, ^down}
    assert_receive {:exec_message, {:exec_probe, ^gate}}
    send(worker, {:release, gate})
    assert {:ok, _} = Task.await(caller)
    eventually(fn -> Server.status(server).phase == :idle end)
    assert Server.status(server).state_version == 1
  end

  test "Agent death stops its linked Exec and Action work", %{jido: jido} do
    id = unique_id("owned-exec-stop")
    {:ok, agent} = Jido.start_agent(jido, OwnedExecutionAgent, id: id)
    gate = make_ref()

    Server.cast(agent, signal("owned.action", %{test: self(), gate: gate, label: :kill}))
    assert_receive {:owned_execution, :kill, action_worker}, 2_000

    {:running, state} = :sys.get_state(agent)
    exec_root = state.active.exec_handle.pid
    action_ref = Process.monitor(action_worker)
    exec_ref = Process.monitor(exec_root)

    Process.exit(agent, :kill)

    assert_receive {:DOWN, ^exec_ref, :process, ^exec_root, _reason}, 2_000
    assert_receive {:DOWN, ^action_ref, :process, ^action_worker, _reason}, 2_000
  end

  test "starts and owns a Plugin runtime child outside Agent state", %{jido: jido} do
    {:ok, pid} =
      Jido.start_agent(jido, PluginRuntimeAgent, id: unique_id("plugin-runtime"))

    agent =
      eventually_agent(pid, fn agent ->
        agent.state.events == [:plugin_booted] and agent.state.boot.calls == 1
      end)

    refute Map.has_key?(agent.state, :children)
    refute Enum.any?(Map.values(agent.state), &is_pid/1)

    child = eventually(fn -> Server.children(pid)[{:plugin, BootPlugin}] end)
    assert child.kind == :plugin
    assert child.module == BootPlugin
    assert Process.alive?(child.pid)

    monitor = Process.monitor(child.pid)
    assert :ok = Jido.stop_agent(jido, pid)
    assert_receive {:DOWN, ^monitor, :process, _pid, :shutdown}, 2_000
  end

  test "does not report the Agent ready before its Plugin runtime is ready", %{jido: jido} do
    Process.register(self(), :jido_agent_plugin_readiness_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_plugin_readiness_test) == self() do
        Process.unregister(:jido_agent_plugin_readiness_test)
      end
    end)

    task =
      Task.async(fn ->
        Jido.start_agent(jido, ReadinessAgent, id: unique_id("plugin-readiness"))
      end)

    assert_receive {:plugin_initializing, runtime}
    refute Task.yield(task, 50)

    send(runtime, :release)
    assert {:ok, pid} = Task.await(task, 2_000)
    assert Process.alive?(pid)
  end

  test "does not overlap Plugin runtime generations after an Agent crash", %{jido: jido} do
    Process.register(self(), :jido_agent_generation_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_generation_test) == self() do
        Process.unregister(:jido_agent_generation_test)
      end
    end)

    id = unique_id("plugin-generation")
    {:ok, agent} = Jido.start_agent(jido, GenerationAgent, id: id)
    assert_receive {:generation_started, first_runtime}, 2_000

    on_exit(fn ->
      if Process.alive?(first_runtime), do: send(first_runtime, :release_generation_stop)
    end)

    Process.exit(agent, :kill)
    assert_receive {:generation_stopping, ^first_runtime}, 2_000

    send(first_runtime, :release_generation_stop)
    assert_receive {:generation_started, second_runtime}, 2_000
    refute second_runtime == first_runtime
    refute Process.alive?(first_runtime)

    restarted = eventually(fn -> Jido.whereis_agent(jido, id) end)
    assert Process.alive?(restarted)
  end

  test "Plugin child lookup stays responsive while restart readiness reads Agent state", %{
    jido: jido
  } do
    Process.register(self(), :jido_agent_fresh_runtime_test)
    on_exit(fn -> :persistent_term.erase({FreshRuntimePlugin, :pause_restart}) end)
    {:ok, server} = Jido.start_agent(jido, FreshRuntimeAgent, id: unique_id("readiness-state"))
    assert_receive {:fresh_runtime_started, first, %{value: 0}}, 2_000
    assert_receive {:fresh_runtime_ready, ^first, %{value: 0}}, 2_000
    assert {:ok, _} = Server.call(server, signal("runtime.fresh", %{value: 7}))
    eventually(fn -> Server.status(server).phase == :idle end)
    {_, state} = :sys.get_state(server)
    child = Jido.AgentServer.State.child(state, {:plugin, FreshRuntimePlugin})
    :persistent_term.put({FreshRuntimePlugin, :pause_restart}, true)
    Process.exit(first, :kill)
    assert_receive {:fresh_load_waiting, restarted}, 2_000
    assert_receive {:fresh_readiness_waiting, _waiter, ^restarted}, 2_000
    lookup = Task.async(fn -> Jido.AgentServer.PluginChild.child_pid(child.lifecycle_pid) end)

    try do
      assert Task.yield(lookup, 500) == {:ok, :restarting}
      assert {:ok, %{value: 7}} = Server.plugin_state(server, FreshRuntimePlugin, 500)
      assert Server.children(server, 500)[{:plugin, FreshRuntimePlugin}].pid == first
    after
      send(restarted, :release_fresh_load)
      Task.shutdown(lookup, :brutal_kill)
    end

    assert_receive {:fresh_runtime_started, ^restarted, %{value: 7}}, 2_000
    assert_receive {:fresh_runtime_ready, ^restarted, %{value: 7}}, 2_000
    eventually(fn -> Server.children(server)[{:plugin, FreshRuntimePlugin}].pid == restarted end)
    assert Process.alive?(server)
  end

  test "refreshes Plugin state and readiness after an internal runtime restart", %{jido: jido} do
    Process.register(self(), :jido_agent_fresh_runtime_test)

    on_exit(fn ->
      if Process.whereis(:jido_agent_fresh_runtime_test) == self() do
        Process.unregister(:jido_agent_fresh_runtime_test)
      end
    end)

    {:ok, pid} = Jido.start_agent(jido, FreshRuntimeAgent, id: unique_id("fresh-runtime"))

    assert_receive {:fresh_runtime_started, first_runtime, %{value: 0}}, 2_000
    assert_receive {:fresh_runtime_ready, ^first_runtime, %{value: 0}}, 2_000

    assert {:ok, agent} =
             Server.call(pid, signal("runtime.fresh", %{value: 7}))

    assert agent.state.fresh_runtime.value == 7
    eventually(fn -> Server.status(pid).phase == :idle end)

    child = Server.children(pid)[{:plugin, FreshRuntimePlugin}]
    assert child.pid == first_runtime
    monitor = Process.monitor(first_runtime)
    Process.exit(first_runtime, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first_runtime, :killed}, 2_000

    assert_receive {:fresh_runtime_started, restarted_runtime, %{value: 7}}, 2_000
    refute restarted_runtime == first_runtime
    assert_receive {:fresh_runtime_ready, ^restarted_runtime, %{value: 7}}, 2_000

    eventually(fn ->
      Server.children(pid)[{:plugin, FreshRuntimePlugin}].pid == restarted_runtime
    end)
  end

  test "restores the last committed Agent when a required Plugin runtime is lost", %{jido: jido} do
    id = unique_id("required-plugin")
    {:ok, pid} = Jido.start_agent(jido, RuntimeAgent, id: id)

    assert {:ok, committed_agent} =
             Server.call(pid, signal("runtime.record", %{event: :committed_before_restart}))

    assert committed_agent.state.events == [:committed_before_restart]
    assert Server.status(pid).state_version == 1

    {_phase, state} = :sys.get_state(pid)
    plugin = state.children[{:plugin, Scheduler}]
    monitor = Process.monitor(pid)

    Process.exit(plugin.lifecycle_pid, :kill)

    assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 2_000

    restarted_pid =
      eventually(
        fn ->
          case Jido.whereis_agent(jido, id) do
            new_pid when is_pid(new_pid) and new_pid != pid -> new_pid
            _other -> nil
          end
        end,
        timeout: 3_000
      )

    restarted_agent = Server.agent(restarted_pid)
    assert restarted_agent.state.events == [:committed_before_restart]
    assert restarted_agent.state.ticks == 0
    assert restarted_agent.state.scheduler == %{cron: %{}}
    assert Server.status(restarted_pid).state_version == 1
  end
end
