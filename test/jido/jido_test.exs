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

  describe "stop_agent/2 with non-existent id" do
    test "returns error when agent not found", %{jido: jido} do
      assert {:error, :not_found} = Jido.stop_agent(jido, "non-existent-agent-id")
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
