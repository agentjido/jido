defmodule JidoTest.PersistTest do
  use JidoTest.Case, async: true

  alias Jido.Persist
  alias Jido.Storage.ETS
  alias Jido.Thread
  alias JidoTest.PersistTest.CustomAgent
  alias JidoTest.PersistTest.TestAgent

  defmodule TestAgent do
    use Jido.Agent,
      name: "test_agent",
      schema: [
        counter: [type: :integer, default: 0],
        status: [type: :atom, default: :idle]
      ]

    @impl true
    def signal_routes(_ctx), do: []
  end

  defmodule CustomAgent do
    use Jido.Agent,
      name: "custom_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def checkpoint(agent, _ctx) do
      {:ok,
       %{
         version: 99,
         agent_module: __MODULE__,
         id: agent.id,
         state: %{value: agent.state.value, serialized_by: :custom},
         marker: :custom_checkpoint,
         thread: nil
       }}
    end

    @impl true
    def restore(data, _ctx) do
      agent = new(id: data.id)

      restored_state =
        agent.state
        |> Map.merge(data.state || %{})
        |> Map.put(:restored_by, :custom)

      {:ok, %{agent | state: restored_state}}
    end
  end

  defp unique_table do
    :"persist_test_#{System.unique_integer([:positive])}"
  end

  defp storage(table) do
    {ETS, table: table}
  end

  describe "hibernate/2" do
    test "hibernates agent without thread" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-1")
      agent = %{agent | state: %{agent.state | counter: 42, status: :active}}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({TestAgent, "agent-1"}, table: table)
      assert checkpoint.id == "agent-1"
      assert checkpoint.state.counter == 42
      assert checkpoint.state.status == :active
      assert checkpoint.thread == nil
    end

    test "hibernates agent with thread (thread is flushed first)" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-2")

      thread =
        Thread.new(id: "thread-2")
        |> Thread.append(%{kind: :message, payload: %{content: "hello"}})
        |> Thread.append(%{kind: :message, payload: %{content: "world"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, loaded_thread} = ETS.load_thread("thread-2", table: table)
      assert Thread.entry_count(loaded_thread) == 2

      {:ok, checkpoint} = ETS.get_checkpoint({TestAgent, "agent-2"}, table: table)
      assert checkpoint.thread == %{id: "thread-2", rev: 2}
    end

    test "uses custom checkpoint callback when implemented" do
      table = unique_table()
      agent = CustomAgent.new(id: "custom-1")
      agent = %{agent | state: %{agent.state | value: "custom_value"}}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({CustomAgent, "custom-1"}, table: table)
      assert checkpoint.id == "custom-1"
      assert checkpoint.state.value == "custom_value"
      assert checkpoint.state.serialized_by == :custom
      assert checkpoint.marker == :custom_checkpoint
      assert checkpoint.agent_module == CustomAgent
    end

    test "checkpoint never contains full Thread struct" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-3")

      thread =
        Thread.new(id: "thread-3")
        |> Thread.append(%{kind: :message, payload: %{content: "test"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({TestAgent, "agent-3"}, table: table)

      refute is_struct(checkpoint.thread, Thread)
      refute Map.has_key?(checkpoint.state, :__thread__)
    end

    test "checkpoint contains thread pointer %{id, rev}" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-4")

      thread =
        Thread.new(id: "thread-4")
        |> Thread.append(%{kind: :message, payload: %{content: "one"}})
        |> Thread.append(%{kind: :message, payload: %{content: "two"}})
        |> Thread.append(%{kind: :message, payload: %{content: "three"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({TestAgent, "agent-4"}, table: table)

      assert checkpoint.thread == %{id: "thread-4", rev: 3}
      assert Map.keys(checkpoint.thread) |> Enum.sort() == [:id, :rev]
    end
  end

  describe "hibernate/4" do
    test "uses explicit key instead of agent.id" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-id-ignored")
      explicit_key = {:pool, :user_123}

      assert :ok = Persist.hibernate(storage(table), TestAgent, explicit_key, agent)
      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, explicit_key)
      assert thawed.id == "agent-id-ignored"
    end
  end

  describe "thaw/3" do
    test "returns {:error, :not_found} for missing agent" do
      table = unique_table()
      ETS.put_checkpoint({TestAgent, "nonexistent"}, %{}, table: table)
      ETS.delete_checkpoint({TestAgent, "nonexistent"}, table: table)

      assert {:error, :not_found} = Persist.thaw(storage(table), TestAgent, "nonexistent")
    end

    test "thaws agent without thread" do
      table = unique_table()
      agent = TestAgent.new(id: "thaw-1")
      agent = %{agent | state: %{agent.state | counter: 100, status: :completed}}

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "thaw-1")
      assert thawed.id == "thaw-1"
      assert thawed.state.counter == 100
      assert thawed.state.status == :completed
      refute Map.has_key?(thawed.state, :__thread__)
    end

    test "thaws agent with thread (thread is rehydrated)" do
      table = unique_table()
      agent = TestAgent.new(id: "thaw-2")

      thread =
        Thread.new(id: "thaw-thread-2")
        |> Thread.append(%{kind: :message, payload: %{role: "user", content: "hello"}})
        |> Thread.append(%{kind: :message, payload: %{role: "assistant", content: "hi"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "thaw-2")
      assert thawed.state[:__thread__] != nil

      rehydrated_thread = thawed.state[:__thread__]
      assert rehydrated_thread.id == "thaw-thread-2"
      assert Thread.entry_count(rehydrated_thread) == 2
    end

    test "uses custom restore callback when implemented" do
      table = unique_table()
      agent = CustomAgent.new(id: "thaw-custom")
      agent = %{agent | state: %{agent.state | value: "restored_value"}}

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), CustomAgent, "thaw-custom")
      assert thawed.id == "thaw-custom"
      assert thawed.state.value == "restored_value"
      assert thawed.state.restored_by == :custom
    end

    test "returns {:error, :missing_thread} if thread pointer exists but thread not in storage" do
      table = unique_table()

      checkpoint = %{
        version: 1,
        agent_module: TestAgent,
        id: "orphan-1",
        state: %{counter: 0, status: :idle},
        thread: %{id: "missing-thread", rev: 5}
      }

      :ok = ETS.put_checkpoint({TestAgent, "orphan-1"}, checkpoint, table: table)

      assert {:error, :missing_thread} = Persist.thaw(storage(table), TestAgent, "orphan-1")
    end

    test "returns {:error, :thread_mismatch} if thread rev doesn't match checkpoint" do
      table = unique_table()

      {:ok, _thread} =
        ETS.append_thread(
          "mismatch-thread",
          [
            %{kind: :message, payload: %{content: "one"}},
            %{kind: :message, payload: %{content: "two"}}
          ],
          table: table
        )

      checkpoint = %{
        version: 1,
        agent_module: TestAgent,
        id: "mismatch-1",
        state: %{counter: 0, status: :idle},
        thread: %{id: "mismatch-thread", rev: 10}
      }

      :ok = ETS.put_checkpoint({TestAgent, "mismatch-1"}, checkpoint, table: table)

      assert {:error, :thread_mismatch} = Persist.thaw(storage(table), TestAgent, "mismatch-1")
    end
  end

  describe "round-trip" do
    test "hibernate then thaw returns equivalent agent" do
      table = unique_table()
      agent = TestAgent.new(id: "roundtrip-1")
      agent = %{agent | state: %{agent.state | counter: 999, status: :processing}}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "roundtrip-1")

      assert thawed.id == agent.id
      assert thawed.__struct__ == agent.__struct__
    end

    test "state is preserved correctly" do
      table = unique_table()
      agent = TestAgent.new(id: "roundtrip-2")
      agent = %{agent | state: %{agent.state | counter: 12_345, status: :hibernated}}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "roundtrip-2")

      assert thawed.state.counter == 12_345
      assert thawed.state.status == :hibernated
    end

    test "thread is preserved correctly with all entries" do
      table = unique_table()
      agent = TestAgent.new(id: "roundtrip-3")

      entries = [
        %{kind: :message, payload: %{role: "user", content: "first"}},
        %{kind: :tool_call, payload: %{name: "search", args: %{q: "test"}}},
        %{kind: :tool_result, payload: %{result: "found"}},
        %{kind: :message, payload: %{role: "assistant", content: "done"}}
      ]

      thread =
        Thread.new(id: "roundtrip-thread-3")
        |> Thread.append(entries)

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "roundtrip-3")

      rehydrated = thawed.state[:__thread__]
      assert rehydrated.id == "roundtrip-thread-3"
      assert Thread.entry_count(rehydrated) == 4

      entry_list = Thread.to_list(rehydrated)
      assert Enum.at(entry_list, 0).kind == :message
      assert Enum.at(entry_list, 0).payload.role == "user"
      assert Enum.at(entry_list, 1).kind == :tool_call
      assert Enum.at(entry_list, 2).kind == :tool_result
      assert Enum.at(entry_list, 3).kind == :message
      assert Enum.at(entry_list, 3).payload.role == "assistant"
    end

    test "multiple hibernate cycles update correctly" do
      table = unique_table()
      agent = TestAgent.new(id: "multi-1")

      agent = %{agent | state: %{agent.state | counter: 1}}
      :ok = Persist.hibernate(storage(table), agent)

      {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "multi-1")
      assert thawed.state.counter == 1

      updated = %{thawed | state: %{thawed.state | counter: 2}}
      :ok = Persist.hibernate(storage(table), updated)

      {:ok, thawed2} = Persist.thaw(storage(table), TestAgent, "multi-1")
      assert thawed2.state.counter == 2
    end
  end

  describe "integration with Jido instance" do
    test "hibernate and thaw with Jido instance struct" do
      table = unique_table()
      jido_instance = %{storage: {ETS, table: table}}

      agent = TestAgent.new(id: "jido-instance-1")
      agent = %{agent | state: %{agent.state | counter: 777}}

      assert :ok = Persist.hibernate(jido_instance, agent)
      assert {:ok, thawed} = Persist.thaw(jido_instance, TestAgent, "jido-instance-1")

      assert thawed.state.counter == 777
    end

    test "hibernate and thaw with thread using Jido instance" do
      table = unique_table()
      jido_instance = %{storage: {ETS, table: table}}

      agent = TestAgent.new(id: "jido-instance-2")

      thread =
        Thread.new(id: "jido-instance-thread")
        |> Thread.append(%{kind: :message, payload: %{content: "via jido"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(jido_instance, agent)
      {:ok, thawed} = Persist.thaw(jido_instance, TestAgent, "jido-instance-2")

      assert thawed.state[:__thread__].id == "jido-instance-thread"
      assert Thread.entry_count(thawed.state[:__thread__]) == 1
    end
  end

  describe "edge cases" do
    test "empty thread (no entries) does not create thread in storage" do
      table = unique_table()
      agent = TestAgent.new(id: "empty-thread-1")

      thread = Thread.new(id: "empty-thread")
      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)

      assert :not_found = ETS.load_thread("empty-thread", table: table)
    end

    test "repeated hibernate does not duplicate thread entries" do
      table = unique_table()
      agent = TestAgent.new(id: "conflict-1")

      thread =
        Thread.new(id: "conflict-thread")
        |> Thread.append(%{kind: :message, payload: %{content: "test"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)
      :ok = Persist.hibernate(storage(table), agent)

      {:ok, loaded} = ETS.load_thread("conflict-thread", table: table)
      assert Thread.entry_count(loaded) == 1
    end

    test "checkpoint with thread enforces invariants (no __thread__ in state)" do
      table = unique_table()
      agent = CustomAgent.new(id: "custom-thread-1")
      agent = %{agent | state: %{agent.state | value: "with_thread"}}

      thread =
        Thread.new(id: "custom-thread")
        |> Thread.append(%{kind: :note, payload: %{text: "custom note"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({CustomAgent, "custom-thread-1"}, table: table)

      assert checkpoint.thread == %{id: "custom-thread", rev: 1}
      refute Map.has_key?(checkpoint.state || %{}, :__thread__)
    end
  end
end
