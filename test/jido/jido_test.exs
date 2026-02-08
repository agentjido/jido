defmodule JidoTest.JidoTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestAgents.Minimal

  describe "scheduler_name/1" do
    test "returns scheduler name for jido instance" do
      assert Jido.scheduler_name(MyApp.Jido) == MyApp.Jido.Scheduler
    end

    test "works with nested module names" do
      assert Jido.scheduler_name(MyApp.Sub.Jido) == MyApp.Sub.Jido.Scheduler
    end
  end

  describe "agent_pool_name/2" do
    test "returns pool name for jido instance and pool" do
      # Module.concat keeps the atom as-is (lowercase) when joining
      result = Jido.agent_pool_name(MyApp.Jido, :workers)
      assert result == :"Elixir.MyApp.Jido.AgentPool.workers"
    end

    test "works with different pool names" do
      result = Jido.agent_pool_name(MyApp.Jido, :processors)
      assert result == :"Elixir.MyApp.Jido.AgentPool.processors"
    end

    test "works with nested module names" do
      result = Jido.agent_pool_name(MyApp.Sub.Jido, :pool)
      assert result == :"Elixir.MyApp.Sub.Jido.AgentPool.pool"
    end
  end

  describe "generate_id/0" do
    test "generates a unique identifier" do
      id1 = Jido.generate_id()
      id2 = Jido.generate_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
    end
  end

  describe "script convenience APIs" do
    test "default_instance/0 and start/1 wrappers are idempotent" do
      assert Jido.default_instance() == Jido.Default

      name = :"jido_start_wrapper_#{System.unique_integer([:positive])}"
      assert {:ok, pid} = Jido.start(name: name)
      assert {:ok, ^pid} = Jido.start(name: name)
      assert :ok = Jido.stop(name)
    end
  end

  describe "stop_agent/2 with non-existent id" do
    test "is idempotent when agent is not found", %{jido: jido} do
      assert :ok = Jido.stop_agent(jido, "non-existent-agent-id")
    end
  end

  describe "stop/1" do
    test "returns :ok for unknown instance and stops a running instance" do
      missing = :"jido_missing_#{System.unique_integer([:positive])}"
      assert :ok = Jido.stop(missing)

      running = :"jido_running_#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_link(name: running)
      assert Process.alive?(pid)

      assert :ok = Jido.stop(running)
      refute Process.alive?(pid)
      assert :ok = Jido.stop(running)
    end
  end

  describe "supervisor race hardening" do
    test "start_agent/3 returns explicit missing supervisor error for unknown instance" do
      missing_instance = :"missing_jido_#{System.unique_integer([:positive])}"
      expected_sup = Jido.agent_supervisor_name(missing_instance)

      assert {:error, {:missing_supervisor, ^expected_sup}} =
               Jido.start_agent(missing_instance, Minimal, id: "missing-start")
    end

    test "stop_agent/2 by pid returns :not_found when instance supervisor is unavailable" do
      missing_instance = :"missing_jido_#{System.unique_integer([:positive])}"
      pid = self()

      assert {:error, :not_found} = Jido.stop_agent(missing_instance, pid)
    end
  end

  describe "dynamic supervisor guardrails" do
    test "respects configured max_agents limit" do
      instance = :"jido_max_children_#{System.unique_integer([:positive])}"
      {:ok, _pid} = start_supervised({Jido, name: instance, max_agents: 1})

      assert {:ok, _} = Jido.start_agent(instance, Minimal, id: "max-agents-1")
      assert {:error, :max_children} = Jido.start_agent(instance, Minimal, id: "max-agents-2")
    end

    test "init/1 applies configurable restart intensity settings" do
      instance = :"jido_restart_cfg_#{System.unique_integer([:positive])}"

      assert {:ok, {_flags, children}} =
               Jido.init(name: instance, max_restarts: 77, max_seconds: 11)

      agent_sup_name = Jido.agent_supervisor_name(instance)
      spec = Enum.find(children, &(&1.id == agent_sup_name))

      assert %{start: {DynamicSupervisor, :start_link, [opts]}} = spec
      assert opts[:max_restarts] == 77
      assert opts[:max_seconds] == 11
    end
  end

  describe "registry and counting helpers" do
    test "whereis/list_agents/agent_count reflect running agents", %{jido: jido} do
      id1 = "helper-agent-1"
      id2 = "helper-agent-2"

      assert Jido.agent_count(jido) == 0

      {:ok, pid1} = Jido.start_agent(jido, Minimal, id: id1)
      {:ok, pid2} = Jido.start_agent(jido, Minimal, id: id2)

      assert Jido.whereis(jido, id1) == pid1
      assert Jido.whereis(jido, id2) == pid2
      assert Jido.whereis(jido, "unknown-id") == nil

      assert {id1, pid1} in Jido.list_agents(jido)
      assert {id2, pid2} in Jido.list_agents(jido)
      assert Jido.agent_count(jido) == 2
    end

    test "agent_count/1 returns zero for missing instance supervisor" do
      missing = :"jido_missing_sup_#{System.unique_integer([:positive])}"
      assert Jido.agent_count(missing) == 0
    end
  end

  describe "start_agent/2 default options" do
    test "starts an agent without explicit opts", %{jido: jido} do
      assert {:ok, pid} = Jido.start_agent(jido, Minimal)
      assert is_pid(pid)
    end
  end

  describe "await delegates" do
    test "await/3 delegates to Jido.Await.completion", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "await-delegate-test")

      result = Jido.await(pid, 50)
      assert {:error, {:timeout, _details}} = result
    end

    test "await_all/3 delegates to Jido.Await.all", %{jido: jido} do
      {:ok, pid1} = Jido.start_agent(jido, Minimal, id: "await-all-delegate-1")
      {:ok, pid2} = Jido.start_agent(jido, Minimal, id: "await-all-delegate-2")

      result = Jido.await_all([pid1, pid2], 50)
      assert {:error, :timeout} = result
    end

    test "await_any/3 delegates to Jido.Await.any", %{jido: jido} do
      {:ok, pid1} = Jido.start_agent(jido, Minimal, id: "await-any-delegate-1")
      {:ok, pid2} = Jido.start_agent(jido, Minimal, id: "await-any-delegate-2")

      result = Jido.await_any([pid1, pid2], 50)
      assert match?({:error, _}, result)
    end

    test "get_children/1 delegates to Jido.Await", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "get-children-delegate")

      {:ok, children} = Jido.get_children(pid)
      assert children == %{}
    end

    test "get_child/2 delegates to Jido.Await", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "get-child-delegate")

      result = Jido.get_child(pid, :nonexistent)
      assert {:error, :child_not_found} = result
    end

    test "alive?/1 delegates to Jido.Await", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "alive-delegate")

      assert Jido.alive?(pid) == true
    end

    test "cancel/2 delegates to Jido.Await", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "cancel-delegate")

      assert :ok = Jido.cancel(pid)
      assert :ok = Jido.cancel(pid, reason: :user_cancelled)
    end
  end

  describe "discovery delegates" do
    test "list_actions/1 delegates to Jido.Discovery" do
      actions = Jido.list_actions()
      assert is_list(actions)
    end

    test "list_sensors/1 delegates to Jido.Discovery" do
      sensors = Jido.list_sensors()
      assert is_list(sensors)
    end

    test "list_plugins/1 delegates to Jido.Discovery" do
      plugins = Jido.list_plugins()
      assert is_list(plugins)
    end

    test "list_demos/1 delegates to Jido.Discovery" do
      demos = Jido.list_demos()
      assert is_list(demos)
    end

    test "get_action_by_slug/1 delegates to Jido.Discovery" do
      result = Jido.get_action_by_slug("nonexistent-action-slug")
      assert result == nil or is_map(result)
    end

    test "get_sensor_by_slug/1 delegates to Jido.Discovery" do
      result = Jido.get_sensor_by_slug("nonexistent-sensor-slug")
      assert result == nil or is_map(result)
    end

    test "get_plugin_by_slug/1 delegates to Jido.Discovery" do
      result = Jido.get_plugin_by_slug("nonexistent-plugin-slug")
      assert result == nil or is_map(result)
    end

    test "refresh_discovery/0 delegates to Jido.Discovery" do
      result = Jido.refresh_discovery()
      assert result == :ok
    end
  end

  describe "await_child/4 delegate" do
    test "await_child/4 returns timeout when child not found", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, Minimal, id: "await-child-delegate")

      result = Jido.await_child(pid, :nonexistent, 50)
      assert {:error, :timeout} = result
    end
  end
end
