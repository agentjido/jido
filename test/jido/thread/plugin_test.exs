defmodule JidoTest.Thread.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Instance, as: PluginInstance
  alias Jido.Thread
  alias Jido.Thread.Plugin, as: ThreadPlugin

  describe "plugin metadata" do
    test "name is thread" do
      assert ThreadPlugin.name() == "thread"
    end

    test "state_key is :__thread__" do
      assert ThreadPlugin.state_key() == :__thread__
    end

    test "is singleton" do
      assert ThreadPlugin.singleton?() == true
    end

    test "has thread capability" do
      assert :thread in ThreadPlugin.capabilities()
    end

    test "has no actions" do
      assert ThreadPlugin.actions() == []
    end

    test "schema is nil (no auto-initialization)" do
      assert ThreadPlugin.schema() == nil
    end
  end

  describe "mount/2" do
    test "returns {:ok, nil} (does not create a thread)" do
      assert {:ok, nil} = ThreadPlugin.mount(nil, %{})
    end
  end

  describe "manifest" do
    test "singleton is true in manifest" do
      manifest = ThreadPlugin.manifest()
      assert manifest.singleton == true
    end

    test "state_key is :__thread__ in manifest" do
      manifest = ThreadPlugin.manifest()
      assert manifest.state_key == :__thread__
    end
  end

  describe "on_checkpoint/2" do
    test "externalizes a thread struct" do
      thread = Thread.new(id: "t-1")
      thread = Thread.append(thread, %{kind: :message, payload: %{text: "hello"}})

      assert {:externalize, :thread, %{id: "t-1", rev: 1}} =
               ThreadPlugin.on_checkpoint(thread, %{})
    end

    test "keeps nil state" do
      assert :keep = ThreadPlugin.on_checkpoint(nil, %{})
    end

    test "externalizes thread with correct rev count" do
      thread =
        Thread.new(id: "t-2")
        |> Thread.append(%{kind: :message, payload: %{text: "one"}})
        |> Thread.append(%{kind: :message, payload: %{text: "two"}})
        |> Thread.append(%{kind: :message, payload: %{text: "three"}})

      assert {:externalize, :thread, %{id: "t-2", rev: 3}} =
               ThreadPlugin.on_checkpoint(thread, %{})
    end
  end

  describe "on_restore/2" do
    test "returns {:ok, nil} (persist handles IO rehydration)" do
      assert {:ok, nil} = ThreadPlugin.on_restore(%{id: "t-1", rev: 5}, %{})
    end
  end

  describe "agent integration" do
    defmodule AgentWithThread do
      use Jido.Agent, name: "thread_plugin_test_agent"
    end

    defmodule AgentWithoutThread do
      use Jido.Agent,
        name: "thread_plugin_test_no_thread",
        default_plugins: %{__thread__: false}
    end

    test "agent includes thread plugin by default" do
      modules = AgentWithThread.plugins()
      assert Jido.Thread.Plugin in modules
    end

    test "agent state does not contain :__thread__ key initially" do
      agent = AgentWithThread.new()
      refute Map.has_key?(agent.state, :__thread__)
    end

    test "agent can disable thread plugin" do
      modules = AgentWithoutThread.plugins()
      refute Jido.Thread.Plugin in modules
    end

    test "thread can be attached after creation via Thread.Agent" do
      agent = AgentWithThread.new()
      agent = Thread.Agent.ensure(agent)
      assert %Thread{} = Thread.Agent.get(agent)
    end

    test "cannot alias thread plugin" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        PluginInstance.new({Jido.Thread.Plugin, as: :my_thread})
      end
    end
  end
end
