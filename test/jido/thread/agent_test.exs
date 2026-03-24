defmodule JidoTest.Thread.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  defp create_agent do
    %Agent{
      id: "test-agent-1",
      state: %{}
    }
  end

  describe "key/0" do
    test "returns :__thread__" do
      assert ThreadAgent.key() == :__thread__
    end
  end

  describe "get/2" do
    test "returns nil when no thread present" do
      agent = create_agent()
      assert ThreadAgent.get(agent) == nil
    end

    test "returns default when no thread present" do
      agent = create_agent()
      default = Thread.new()
      assert ThreadAgent.get(agent, default) == default
    end

    test "returns thread when present" do
      thread = Thread.new(id: "test-thread")
      agent = %{create_agent() | state: %{__thread__: thread}}
      assert ThreadAgent.get(agent) == thread
    end
  end

  describe "put/2" do
    test "stores thread in agent state" do
      agent = create_agent()
      thread = Thread.new(id: "test-thread")

      updated = ThreadAgent.put(agent, thread)

      assert updated.state[:__thread__] == thread
      assert ThreadAgent.get(updated) == thread
    end

    test "preserves other state keys" do
      agent = %{create_agent() | state: %{foo: :bar}}
      thread = Thread.new()

      updated = ThreadAgent.put(agent, thread)

      assert updated.state[:foo] == :bar
      assert updated.state[:__thread__] == thread
    end
  end

  describe "update/2" do
    test "updates thread using function" do
      thread = Thread.new(id: "test-thread")
      agent = ThreadAgent.put(create_agent(), thread)

      updated =
        ThreadAgent.update(agent, fn t ->
          Thread.append(t, %{kind: :message, payload: %{text: "hello"}})
        end)

      result_thread = ThreadAgent.get(updated)
      assert Thread.entry_count(result_thread) == 1
    end

    test "passes nil to function when no thread" do
      agent = create_agent()

      updated =
        ThreadAgent.update(agent, fn t ->
          assert t == nil
          Thread.new(id: "created-in-update")
        end)

      assert ThreadAgent.get(updated).id == "created-in-update"
    end
  end

  describe "ensure/2" do
    test "creates thread if missing" do
      agent = create_agent()
      assert ThreadAgent.has_thread?(agent) == false

      updated = ThreadAgent.ensure(agent)

      assert ThreadAgent.has_thread?(updated) == true
      assert %Thread{} = ThreadAgent.get(updated)
    end

    test "passes options to Thread.new" do
      agent = create_agent()

      updated = ThreadAgent.ensure(agent, metadata: %{user_id: "u1"})

      thread = ThreadAgent.get(updated)
      assert thread.metadata == %{user_id: "u1"}
    end

    test "does NOT overwrite existing thread" do
      thread = Thread.new(id: "original-thread", metadata: %{keep: :this})
      agent = ThreadAgent.put(create_agent(), thread)

      updated = ThreadAgent.ensure(agent, metadata: %{new: :metadata})

      result = ThreadAgent.get(updated)
      assert result.id == "original-thread"
      assert result.metadata == %{keep: :this}
    end
  end

  describe "append/3" do
    test "initializes thread if missing and appends entry" do
      agent = create_agent()
      assert ThreadAgent.has_thread?(agent) == false

      updated = ThreadAgent.append(agent, %{kind: :message, payload: %{text: "hi"}})

      assert ThreadAgent.has_thread?(updated) == true
      thread = ThreadAgent.get(updated)
      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).kind == :message
    end

    test "appends to existing thread" do
      thread = Thread.new() |> Thread.append(%{kind: :note, payload: %{text: "first"}})
      agent = ThreadAgent.put(create_agent(), thread)

      updated = ThreadAgent.append(agent, %{kind: :message, payload: %{text: "second"}})

      result = ThreadAgent.get(updated)
      assert Thread.entry_count(result) == 2
      assert Thread.last(result).kind == :message
    end

    test "appends multiple entries" do
      agent = create_agent()

      entries = [
        %{kind: :message, payload: %{role: "user"}},
        %{kind: :message, payload: %{role: "assistant"}}
      ]

      updated = ThreadAgent.append(agent, entries)

      thread = ThreadAgent.get(updated)
      assert Thread.entry_count(thread) == 2
    end

    test "passes options to ensure" do
      agent = create_agent()

      updated =
        ThreadAgent.append(
          agent,
          %{kind: :message, payload: %{}},
          metadata: %{channel: "web"}
        )

      thread = ThreadAgent.get(updated)
      assert thread.metadata == %{channel: "web"}
    end
  end

  describe "has_thread?/1" do
    test "returns false when no thread" do
      agent = create_agent()
      assert ThreadAgent.has_thread?(agent) == false
    end

    test "returns true when thread present" do
      agent = ThreadAgent.put(create_agent(), Thread.new())
      assert ThreadAgent.has_thread?(agent) == true
    end
  end
end
