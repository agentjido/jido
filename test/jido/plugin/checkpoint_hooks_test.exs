defmodule JidoTest.Plugin.CheckpointHooksTest do
  use ExUnit.Case, async: true

  alias Jido.Thread

  defmodule KeepPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "keep_plugin",
      state_key: :kept,
      actions: [],
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule DropPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "drop_plugin",
      state_key: :transient,
      actions: [],
      schema: Zoi.object(%{cache: Zoi.any() |> Zoi.default(nil)})

    @impl Jido.Plugin
    def on_checkpoint(_state, _ctx), do: :drop
  end

  defmodule AgentWithKeepPlugin do
    use Jido.Agent,
      name: "checkpoint_keep_agent",
      default_plugins: false,
      plugins: [KeepPlugin]
  end

  defmodule AgentWithDropPlugin do
    use Jido.Agent,
      name: "checkpoint_drop_agent",
      default_plugins: false,
      plugins: [DropPlugin]
  end

  defmodule AgentWithThreadPlugin do
    use Jido.Agent,
      name: "checkpoint_thread_agent",
      schema: [counter: [type: :integer, default: 0]]
  end

  defmodule AgentWithMixedPlugins do
    use Jido.Agent,
      name: "checkpoint_mixed_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [KeepPlugin, DropPlugin]
  end

  describe "checkpoint with :keep plugin" do
    test "plugin state is included in checkpoint" do
      agent = AgentWithKeepPlugin.new()
      new_state = Map.put(agent.state, :kept, %{value: 42})
      agent = %{agent | state: new_state}

      {:ok, checkpoint} = AgentWithKeepPlugin.checkpoint(agent, %{})

      assert checkpoint.state[:kept] == %{value: 42}
    end
  end

  describe "checkpoint with :drop plugin" do
    test "plugin state is excluded from checkpoint" do
      agent = AgentWithDropPlugin.new()
      new_state = Map.put(agent.state, :transient, %{cache: "big_data"})
      agent = %{agent | state: new_state}

      {:ok, checkpoint} = AgentWithDropPlugin.checkpoint(agent, %{})

      refute Map.has_key?(checkpoint.state, :transient)
    end
  end

  describe "checkpoint with thread plugin (externalize)" do
    test "thread is externalized as pointer" do
      agent = AgentWithThreadPlugin.new()

      thread =
        Thread.new(id: "test-thread")
        |> Thread.append(%{kind: :message, payload: %{text: "hello"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      {:ok, checkpoint} = AgentWithThreadPlugin.checkpoint(agent, %{})

      assert checkpoint.thread == %{id: "test-thread", rev: 1}
      refute Map.has_key?(checkpoint.state, :__thread__)
    end

    test "no thread produces no thread pointer" do
      agent = AgentWithThreadPlugin.new()

      {:ok, checkpoint} = AgentWithThreadPlugin.checkpoint(agent, %{})

      refute Map.has_key?(checkpoint, :thread)
    end

    test "base agent state is preserved alongside thread pointer" do
      agent = AgentWithThreadPlugin.new()

      thread = Thread.new(id: "t-state-test")
      agent = %{agent | state: %{agent.state | counter: 99}}
      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      {:ok, checkpoint} = AgentWithThreadPlugin.checkpoint(agent, %{})

      assert checkpoint.state.counter == 99
      assert checkpoint.thread == %{id: "t-state-test", rev: 0}
    end
  end

  describe "checkpoint with mixed plugins" do
    test "kept plugin stays, dropped plugin removed, thread externalized" do
      agent = AgentWithMixedPlugins.new()

      thread =
        Thread.new(id: "mixed-thread")
        |> Thread.append(%{kind: :message, payload: %{text: "test"}})

      new_state =
        agent.state
        |> Map.put(:kept, %{value: 10})
        |> Map.put(:transient, %{cache: "temp"})
        |> Map.put(:__thread__, thread)

      agent = %{agent | state: new_state}

      {:ok, checkpoint} = AgentWithMixedPlugins.checkpoint(agent, %{})

      assert checkpoint.state[:kept] == %{value: 10}
      refute Map.has_key?(checkpoint.state, :transient)
      refute Map.has_key?(checkpoint.state, :__thread__)
      assert checkpoint.thread == %{id: "mixed-thread", rev: 1}
    end
  end
end
