defmodule JidoExampleTest.CheckpointRestoreTest do
  @moduledoc """
  Example test demonstrating plugin checkpoint/restore hooks.

  This test shows:
  - How on_checkpoint/2 returns :keep, :drop, or {:externalize, key, pointer}
  - How on_restore/2 rehydrates externalized state
  - How Thread.Plugin externalizes thread as a pointer
  - How checkpoint/2 on the agent iterates plugin instances

  Run with: mix test --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Thread

  # ===========================================================================
  # PLUGINS: Different checkpoint strategies
  # ===========================================================================

  defmodule CachePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "cache",
      state_key: :cache,
      actions: []

    @impl Jido.Plugin
    def on_checkpoint(_state, _ctx), do: :drop
  end

  defmodule SessionPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "session",
      state_key: :session,
      actions: []

    @impl Jido.Plugin
    def on_checkpoint(%{id: session_id}, _ctx) do
      {:externalize, :session, %{id: session_id}}
    end

    def on_checkpoint(nil, _ctx), do: :keep
    def on_checkpoint(state, _ctx) when state == %{}, do: :keep

    @impl Jido.Plugin
    def on_restore(%{id: session_id}, _ctx) do
      {:ok, %{id: session_id, restored: true}}
    end
  end

  # ===========================================================================
  # AGENT: Multiple plugins with mixed checkpoint strategies
  # ===========================================================================

  defmodule CheckpointableAgent do
    @moduledoc false
    use Jido.Agent,
      name: "checkpointable_agent",
      description: "Agent with mixed checkpoint plugin strategies",
      schema: [
        counter: [type: :integer, default: 0]
      ],
      plugins: [
        JidoExampleTest.CheckpointRestoreTest.CachePlugin,
        JidoExampleTest.CheckpointRestoreTest.SessionPlugin
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "checkpoint with :keep (default)" do
    test "plugin state using default on_checkpoint is included in checkpoint" do
      agent = CheckpointableAgent.new()
      agent = %{agent | state: %{agent.state | counter: 42}}

      {:ok, checkpoint} = CheckpointableAgent.checkpoint(agent, %{})

      assert checkpoint.state.counter == 42
    end
  end

  describe "checkpoint with :drop" do
    test "CachePlugin state is excluded from checkpoint" do
      agent = CheckpointableAgent.new()
      agent = %{agent | state: Map.put(agent.state, :cache, %{key: "large_value"})}

      {:ok, checkpoint} = CheckpointableAgent.checkpoint(agent, %{})

      refute Map.has_key?(checkpoint.state, :cache)
    end
  end

  describe "checkpoint with :externalize" do
    test "SessionPlugin stores pointer instead of full state" do
      agent = CheckpointableAgent.new()
      agent = %{agent | state: Map.put(agent.state, :session, %{id: "sess-123"})}

      {:ok, checkpoint} = CheckpointableAgent.checkpoint(agent, %{})

      assert checkpoint.session == %{id: "sess-123"}
      refute Map.has_key?(checkpoint.state, :session)
    end

    test "SessionPlugin on_restore rehydrates from pointer" do
      pointer = %{id: "sess-456"}

      {:ok, restored} = SessionPlugin.on_restore(pointer, %{})

      assert restored == %{id: "sess-456", restored: true}
    end
  end

  describe "Thread.Plugin checkpoint" do
    test "thread is externalized as pointer with id and rev" do
      agent = CheckpointableAgent.new()

      thread =
        Thread.new(id: "thread-001")
        |> Thread.append(%{kind: :message, payload: %{text: "hello"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      {:ok, checkpoint} = CheckpointableAgent.checkpoint(agent, %{})

      assert checkpoint.thread == %{id: "thread-001", rev: 1}
      refute Map.has_key?(checkpoint.state, :__thread__)
    end
  end

  describe "mixed checkpoint strategies" do
    test "all plugin strategies applied together in single checkpoint" do
      agent = CheckpointableAgent.new()

      thread =
        Thread.new(id: "mixed-thread")
        |> Thread.append(%{kind: :message, payload: %{text: "test"}})

      new_state =
        agent.state
        |> Map.put(:counter, 99)
        |> Map.put(:cache, %{key: "ephemeral"})
        |> Map.put(:session, %{id: "sess-mixed"})
        |> Map.put(:__thread__, thread)

      agent = %{agent | state: new_state}

      {:ok, checkpoint} = CheckpointableAgent.checkpoint(agent, %{})

      assert checkpoint.state.counter == 99
      refute Map.has_key?(checkpoint.state, :cache)
      refute Map.has_key?(checkpoint.state, :session)
      refute Map.has_key?(checkpoint.state, :__thread__)
      assert checkpoint.session == %{id: "sess-mixed"}
      assert checkpoint.thread == %{id: "mixed-thread", rev: 1}
    end
  end
end
