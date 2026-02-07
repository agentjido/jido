defmodule JidoTest.DiscoveryTest do
  use ExUnit.Case, async: false

  alias Jido.Discovery

  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "discovery_test_action",
      description: "Test action for discovery",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  setup do
    Discovery.refresh()
    :ok
  end

  describe "init_async/0" do
    test "returns a Task" do
      task = Discovery.init_async()
      assert %Task{} = task
      Task.await(task)
    end
  end

  describe "refresh/0" do
    test "refreshes the catalog" do
      assert :ok = Discovery.refresh()
    end
  end

  describe "last_updated/0" do
    test "returns timestamp after initialization" do
      {:ok, timestamp} = Discovery.last_updated()
      assert %DateTime{} = timestamp
    end
  end

  describe "catalog/0" do
    test "returns full catalog" do
      {:ok, catalog} = Discovery.catalog()
      assert Map.has_key?(catalog, :last_updated)
      assert Map.has_key?(catalog, :components)
      assert Map.has_key?(catalog.components, :actions)
      assert Map.has_key?(catalog.components, :sensors)
      assert Map.has_key?(catalog.components, :agents)
      assert Map.has_key?(catalog.components, :plugins)
      assert Map.has_key?(catalog.components, :demos)
    end
  end

  describe "list_actions/1" do
    test "returns a list of actions" do
      actions = Discovery.list_actions()
      assert is_list(actions)
    end

    test "filters by limit" do
      actions = Discovery.list_actions(limit: 2)
      assert length(actions) <= 2
    end

    test "filters by offset" do
      all_actions = Discovery.list_actions()
      offset_actions = Discovery.list_actions(offset: 1)

      if length(all_actions) > 1 do
        assert length(offset_actions) == length(all_actions) - 1
      end
    end

    test "filters by name" do
      actions = Discovery.list_actions(name: "discovery_test")
      assert Enum.all?(actions, fn a -> String.contains?(a[:name] || "", "discovery_test") end)
    end

    test "filters by description" do
      actions = Discovery.list_actions(description: "discovery")
      assert Enum.all?(actions, fn a -> String.contains?(a[:description] || "", "discovery") end)
    end

    test "filters by category" do
      actions = Discovery.list_actions(category: :utility)
      assert Enum.all?(actions, fn a -> a[:category] == :utility end)
    end

    test "filters by tag" do
      actions = Discovery.list_actions(tag: :test)
      assert Enum.all?(actions, fn a -> is_list(a[:tags]) and :test in a[:tags] end)
    end
  end

  describe "list_sensors/1" do
    test "returns a list of sensors" do
      sensors = Discovery.list_sensors()
      assert is_list(sensors)
    end

    test "filters by limit" do
      sensors = Discovery.list_sensors(limit: 1)
      assert length(sensors) <= 1
    end
  end

  describe "list_agents/1" do
    test "returns a list of agents" do
      agents = Discovery.list_agents()
      assert is_list(agents)
    end

    test "filters by limit" do
      agents = Discovery.list_agents(limit: 1)
      assert length(agents) <= 1
    end
  end

  describe "list_plugins/1" do
    test "returns a list of plugins" do
      plugins = Discovery.list_plugins()
      assert is_list(plugins)
    end

    test "filters by limit" do
      plugins = Discovery.list_plugins(limit: 1)
      assert length(plugins) <= 1
    end
  end

  describe "list_demos/1" do
    test "returns a list of demos" do
      demos = Discovery.list_demos()
      assert is_list(demos)
    end

    test "filters by limit" do
      demos = Discovery.list_demos(limit: 1)
      assert length(demos) <= 1
    end
  end

  describe "get_action_by_slug/1" do
    test "returns nil for non-existent slug" do
      assert nil == Discovery.get_action_by_slug("nonexistent_slug_123")
    end

    test "returns action for valid slug" do
      actions = Discovery.list_actions(limit: 1)

      if actions != [] do
        [action | _] = actions
        found = Discovery.get_action_by_slug(action.slug)
        assert found != nil
        assert found.slug == action.slug
      end
    end
  end

  describe "get_sensor_by_slug/1" do
    test "returns nil for non-existent slug" do
      assert nil == Discovery.get_sensor_by_slug("nonexistent_slug_123")
    end
  end

  describe "get_agent_by_slug/1" do
    test "returns nil for non-existent slug" do
      assert nil == Discovery.get_agent_by_slug("nonexistent_slug_123")
    end

    test "returns agent for valid slug" do
      agents = Discovery.list_agents(limit: 1)

      if agents != [] do
        [agent | _] = agents
        found = Discovery.get_agent_by_slug(agent.slug)
        assert found != nil
        assert found.slug == agent.slug
      end
    end
  end

  describe "get_plugin_by_slug/1" do
    test "returns nil for non-existent slug" do
      assert nil == Discovery.get_plugin_by_slug("nonexistent_slug_123")
    end
  end

  describe "get_demo_by_slug/1" do
    test "returns nil for non-existent slug" do
      assert nil == Discovery.get_demo_by_slug("nonexistent_slug_123")
    end
  end

  describe "pagination" do
    test "offset and limit work together" do
      all = Discovery.list_actions()
      page1 = Discovery.list_actions(limit: 2, offset: 0)
      page2 = Discovery.list_actions(limit: 2, offset: 2)

      if length(all) >= 4 do
        assert length(page1) == 2
        assert length(page2) == 2
        assert Enum.at(all, 0) == Enum.at(page1, 0)
        assert Enum.at(all, 2) == Enum.at(page2, 0)
      end
    end

    test "handles invalid limit gracefully" do
      actions = Discovery.list_actions(limit: -1)
      assert is_list(actions)
    end
  end

  describe "catalog not initialized" do
    test "list functions return empty when catalog not initialized" do
      :persistent_term.erase(:jido_discovery_catalog)

      assert [] == Discovery.list_actions()
      assert [] == Discovery.list_sensors()
      assert [] == Discovery.list_agents()
      assert [] == Discovery.list_plugins()
      assert [] == Discovery.list_demos()

      Discovery.refresh()
    end

    test "get_by_slug returns nil when catalog not initialized" do
      :persistent_term.erase(:jido_discovery_catalog)

      assert nil == Discovery.get_action_by_slug("any")
      assert nil == Discovery.get_sensor_by_slug("any")
      assert nil == Discovery.get_agent_by_slug("any")
      assert nil == Discovery.get_plugin_by_slug("any")
      assert nil == Discovery.get_demo_by_slug("any")

      Discovery.refresh()
    end

    test "last_updated returns error when not initialized" do
      :persistent_term.erase(:jido_discovery_catalog)

      assert {:error, :not_initialized} = Discovery.last_updated()

      Discovery.refresh()
    end

    test "catalog returns error when not initialized" do
      :persistent_term.erase(:jido_discovery_catalog)

      assert {:error, :not_initialized} = Discovery.catalog()

      Discovery.refresh()
    end
  end
end
