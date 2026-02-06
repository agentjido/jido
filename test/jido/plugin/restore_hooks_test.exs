defmodule JidoTest.Plugin.RestoreHooksTest do
  use ExUnit.Case, async: true

  alias Jido.Thread

  defmodule ExternalizePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "ext_restore_plugin",
      state_key: :ext,
      actions: [],
      schema: Zoi.object(%{id: Zoi.string(), rev: Zoi.integer() |> Zoi.default(0)})

    @impl Jido.Plugin
    def on_checkpoint(%{id: id, rev: rev}, _ctx) do
      {:externalize, :ext_pointer, %{id: id, rev: rev}}
    end

    def on_checkpoint(nil, _ctx), do: :keep

    @impl Jido.Plugin
    def on_restore(%{id: id}, _ctx) do
      {:ok, %{id: id, restored: true}}
    end
  end

  defmodule KeepPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "keep_restore_plugin",
      state_key: :kept,
      actions: [],
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule DropPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "drop_restore_plugin",
      state_key: :transient,
      actions: [],
      schema: Zoi.object(%{cache: Zoi.any() |> Zoi.default(nil)})

    @impl Jido.Plugin
    def on_checkpoint(_state, _ctx), do: :drop
  end

  defmodule ErrorRestorePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "error_restore_plugin",
      state_key: :err,
      actions: []

    @impl Jido.Plugin
    def on_checkpoint(%{id: id}, _ctx) do
      {:externalize, :err_pointer, %{id: id}}
    end

    def on_checkpoint(nil, _ctx), do: :keep

    @impl Jido.Plugin
    def on_restore(_pointer, _ctx) do
      {:error, :restore_failed}
    end
  end

  defmodule AgentWithExternalizePlugin do
    use Jido.Agent,
      name: "restore_ext_agent",
      default_plugins: false,
      plugins: [ExternalizePlugin]
  end

  defmodule AgentWithKeepPlugin do
    use Jido.Agent,
      name: "restore_keep_agent",
      default_plugins: false,
      plugins: [KeepPlugin]
  end

  defmodule AgentWithDropPlugin do
    use Jido.Agent,
      name: "restore_drop_agent",
      default_plugins: false,
      plugins: [DropPlugin]
  end

  defmodule AgentWithErrorPlugin do
    use Jido.Agent,
      name: "restore_error_agent",
      default_plugins: false,
      plugins: [ErrorRestorePlugin]
  end

  defmodule AgentWithMixedPlugins do
    use Jido.Agent,
      name: "restore_mixed_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [KeepPlugin, DropPlugin, ExternalizePlugin]
  end

  defmodule AgentWithThreadPlugin do
    use Jido.Agent,
      name: "restore_thread_agent",
      schema: [counter: [type: :integer, default: 0]]
  end

  describe "restore calls plugin on_restore/2" do
    test "externalized plugin state is restored via on_restore" do
      agent = AgentWithExternalizePlugin.new()
      agent = %{agent | state: Map.put(agent.state, :ext, %{id: "ext-1", rev: 3})}

      {:ok, checkpoint} = AgentWithExternalizePlugin.checkpoint(agent, %{})

      assert checkpoint.ext_pointer == %{id: "ext-1", rev: 3}
      refute Map.has_key?(checkpoint.state, :ext)
      assert checkpoint.externalized_keys == %{ext_pointer: :ext}

      {:ok, restored} = AgentWithExternalizePlugin.restore(checkpoint, %{})

      assert restored.state[:ext] == %{id: "ext-1", restored: true}
    end

    test "plugin returning {:ok, nil} from on_restore does not set state" do
      agent = AgentWithThreadPlugin.new()

      thread =
        Thread.new(id: "test-thread")
        |> Thread.append(%{kind: :message, payload: %{text: "hello"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      {:ok, checkpoint} = AgentWithThreadPlugin.checkpoint(agent, %{})

      assert checkpoint.thread == %{id: "test-thread", rev: 1}
      assert checkpoint.externalized_keys == %{thread: :__thread__}

      {:ok, restored} = AgentWithThreadPlugin.restore(checkpoint, %{})

      refute Map.has_key?(restored.state, :__thread__) ||
               restored.state[:__thread__] != nil
    end

    test "plugin returning {:error, reason} from on_restore fails restore" do
      agent = AgentWithErrorPlugin.new()
      agent = %{agent | state: Map.put(agent.state, :err, %{id: "err-1"})}

      {:ok, checkpoint} = AgentWithErrorPlugin.checkpoint(agent, %{})

      assert {:error, :restore_failed} = AgentWithErrorPlugin.restore(checkpoint, %{})
    end
  end

  describe "checkpoint/restore symmetry" do
    test "keep plugin: state preserved through checkpoint/restore" do
      agent = AgentWithKeepPlugin.new()
      agent = %{agent | state: Map.put(agent.state, :kept, %{value: 42})}

      {:ok, checkpoint} = AgentWithKeepPlugin.checkpoint(agent, %{})
      {:ok, restored} = AgentWithKeepPlugin.restore(checkpoint, %{})

      assert restored.state[:kept] == %{value: 42}
    end

    test "drop plugin: state excluded from checkpoint, restored to defaults" do
      agent = AgentWithDropPlugin.new()
      agent = %{agent | state: Map.put(agent.state, :transient, %{cache: "big"})}

      {:ok, checkpoint} = AgentWithDropPlugin.checkpoint(agent, %{})
      refute Map.has_key?(checkpoint.state, :transient)

      {:ok, restored} = AgentWithDropPlugin.restore(checkpoint, %{})
      refute restored.state[:transient][:cache] == "big"
    end

    test "externalize plugin: round-trip through checkpoint/restore" do
      agent = AgentWithExternalizePlugin.new()
      agent = %{agent | state: Map.put(agent.state, :ext, %{id: "round-trip", rev: 7})}

      {:ok, checkpoint} = AgentWithExternalizePlugin.checkpoint(agent, %{})
      {:ok, restored} = AgentWithExternalizePlugin.restore(checkpoint, %{})

      assert restored.state[:ext] == %{id: "round-trip", restored: true}
    end

    test "mixed plugins: each type handled correctly through checkpoint/restore" do
      agent = AgentWithMixedPlugins.new()

      thread =
        Thread.new(id: "mixed-thread")
        |> Thread.append(%{kind: :message, payload: %{text: "test"}})

      new_state =
        agent.state
        |> Map.put(:kept, %{value: 10})
        |> Map.put(:transient, %{cache: "temp"})
        |> Map.put(:ext, %{id: "ext-mixed", rev: 2})
        |> Map.put(:__thread__, thread)

      agent = %{agent | state: new_state}

      {:ok, checkpoint} = AgentWithMixedPlugins.checkpoint(agent, %{})

      assert checkpoint.state[:kept] == %{value: 10}
      refute Map.has_key?(checkpoint.state, :transient)
      refute Map.has_key?(checkpoint.state, :__thread__)
      refute Map.has_key?(checkpoint.state, :ext)
      assert checkpoint.ext_pointer == %{id: "ext-mixed", rev: 2}
      assert checkpoint.thread == %{id: "mixed-thread", rev: 1}

      {:ok, restored} = AgentWithMixedPlugins.restore(checkpoint, %{})

      assert restored.state[:kept] == %{value: 10}
      assert restored.state[:ext] == %{id: "ext-mixed", restored: true}
      assert restored.state[:counter] == 0
    end

    test "no externalized_keys in checkpoint when no plugins externalize" do
      agent = AgentWithKeepPlugin.new()
      agent = %{agent | state: Map.put(agent.state, :kept, %{value: 1})}

      {:ok, checkpoint} = AgentWithKeepPlugin.checkpoint(agent, %{})

      refute Map.has_key?(checkpoint, :externalized_keys)
    end

    test "restore without externalized_keys works (backward compatibility)" do
      legacy_checkpoint = %{
        version: 1,
        agent_module: AgentWithExternalizePlugin,
        id: "legacy-1",
        state: %{ext: %{id: "legacy", rev: 1}}
      }

      {:ok, restored} = AgentWithExternalizePlugin.restore(legacy_checkpoint, %{})

      assert restored.state[:ext] == %{id: "legacy", rev: 1}
    end

    test "restore passes config to on_restore context" do
      agent = AgentWithExternalizePlugin.new()
      agent = %{agent | state: Map.put(agent.state, :ext, %{id: "ctx-test", rev: 1})}

      {:ok, checkpoint} = AgentWithExternalizePlugin.checkpoint(agent, %{})
      {:ok, _restored} = AgentWithExternalizePlugin.restore(checkpoint, %{})
    end
  end
end
