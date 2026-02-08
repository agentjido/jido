defmodule JidoExampleTest.PersistenceStorageTest do
  @moduledoc """
  Example test demonstrating agent persistence with storage backends.

  This test shows:
  - How hibernate/2 saves agent state to ETS storage
  - How thaw/3 restores an agent from storage
  - Round-trip hibernate → thaw preserves state
  - Thread state is externalized as a pointer during hibernate
  - Thread is rehydrated from storage during thaw

  Run with: mix test --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Agent
  alias Jido.Persist
  alias Jido.Storage.ETS
  alias Jido.Thread

  # ===========================================================================
  # AGENT: Persistable agent with typed schema
  # ===========================================================================

  defmodule PersistableAgent do
    @moduledoc false
    use Jido.Agent,
      name: "persistable_agent",
      description: "An agent demonstrating persistence with ETS storage",
      schema: [
        counter: [type: :integer, default: 0],
        status: [type: :atom, default: :idle],
        notes: [type: {:list, :string}, default: []]
      ]
  end

  # ===========================================================================
  # HELPERS
  # ===========================================================================

  defp unique_table, do: :"persist_storage_test_#{System.unique_integer([:positive])}"

  defp storage(table), do: {ETS, table: table}

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "hibernate and thaw round-trip" do
    test "basic round-trip preserves agent state" do
      table = unique_table()
      agent = PersistableAgent.new(id: "rt-1")
      agent = %{agent | state: %{agent.state | counter: 42, status: :active, notes: ["hello"]}}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, restored} = Persist.thaw(storage(table), Agent, "rt-1")

      assert restored.id == "rt-1"
      assert restored.state.counter == 42
      assert restored.state.status == :active
      assert restored.state.notes == ["hello"]
    end

    test "thaw returns :not_found for non-existent agent" do
      table = unique_table()

      assert {:error, :not_found} = Persist.thaw(storage(table), Agent, "does-not-exist")
    end

    test "state mutations before hibernate are preserved after thaw" do
      table = unique_table()
      agent = PersistableAgent.new(id: "mutate-1")

      agent = %{agent | state: %{agent.state | counter: 1}}
      agent = %{agent | state: %{agent.state | counter: agent.state.counter + 9}}
      agent = %{agent | state: %{agent.state | status: :processing, notes: ["step1", "step2"]}}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, restored} = Persist.thaw(storage(table), Agent, "mutate-1")

      assert restored.state.counter == 10
      assert restored.state.status == :processing
      assert restored.state.notes == ["step1", "step2"]
    end
  end

  describe "thread handling" do
    test "thread is flushed and externalized during hibernate" do
      table = unique_table()
      agent = PersistableAgent.new(id: "thread-1")

      thread =
        Thread.new(id: "thread-flush-1")
        |> Thread.append(%{kind: :message, payload: %{content: "hello"}})
        |> Thread.append(%{kind: :message, payload: %{content: "world"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({Agent, "thread-1"}, table: table)
      refute Map.has_key?(checkpoint.state, :__thread__)
      assert checkpoint.thread == %{id: "thread-flush-1", rev: 2}

      {:ok, stored_thread} = ETS.load_thread("thread-flush-1", table: table)
      assert Thread.entry_count(stored_thread) == 2
    end

    test "thaw restores thread from storage" do
      table = unique_table()
      agent = PersistableAgent.new(id: "thread-2")
      agent = %{agent | state: %{agent.state | counter: 7}}

      thread =
        Thread.new(id: "thread-restore-1")
        |> Thread.append(%{kind: :message, payload: %{role: "user", content: "question"}})
        |> Thread.append(%{kind: :message, payload: %{role: "assistant", content: "answer"}})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)
      {:ok, restored} = Persist.thaw(storage(table), Agent, "thread-2")

      assert restored.state.counter == 7

      rehydrated = restored.state[:__thread__]
      assert rehydrated.id == "thread-restore-1"
      assert Thread.entry_count(rehydrated) == 2
    end
  end

  describe "multiple agents" do
    test "multiple agents can be stored and retrieved independently" do
      table = unique_table()

      agent_a = PersistableAgent.new(id: "multi-a")
      agent_a = %{agent_a | state: %{agent_a.state | counter: 100, status: :done}}

      agent_b = PersistableAgent.new(id: "multi-b")
      agent_b = %{agent_b | state: %{agent_b.state | counter: 200, notes: ["important"]}}

      :ok = Persist.hibernate(storage(table), agent_a)
      :ok = Persist.hibernate(storage(table), agent_b)

      {:ok, restored_a} = Persist.thaw(storage(table), Agent, "multi-a")
      {:ok, restored_b} = Persist.thaw(storage(table), Agent, "multi-b")

      assert restored_a.state.counter == 100
      assert restored_a.state.status == :done

      assert restored_b.state.counter == 200
      assert restored_b.state.notes == ["important"]
    end
  end
end
