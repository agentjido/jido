defmodule JidoTest.Integration.HibernateThawTest do
  use ExUnit.Case, async: true

  alias Jido.Storage.ETS
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  defmodule WorkflowAgent do
    use Jido.Agent,
      name: "workflow_agent",
      schema: [
        step: [type: :integer, default: 0],
        status: [type: :atom, default: :pending],
        data: [type: :map, default: %{}]
      ]

    @impl true
    def signal_routes, do: []
  end

  defp unique_table do
    :"hibernate_thaw_test_#{System.unique_integer([:positive])}"
  end

  defp create_jido_instance(table) do
    %{storage: {ETS, table: table}}
  end

  describe "basic round-trip: create agent → hibernate → thaw → verify" do
    test "agent id is preserved after hibernate/thaw" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "basic-roundtrip-1")

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "basic-roundtrip-1")

      assert thawed.id == "basic-roundtrip-1"
    end

    test "agent struct type is preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "basic-roundtrip-2")

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "basic-roundtrip-2")

      assert thawed.__struct__ == Jido.Agent
    end

    test "default state values are preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "basic-roundtrip-3")

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "basic-roundtrip-3")

      assert thawed.state.step == 0
      assert thawed.state.status == :pending
      assert thawed.state.data == %{}
    end
  end

  describe "with thread: create agent → attach thread → add entries → hibernate → thaw → verify" do
    test "thread is restored with correct id" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "thread-test-1")

      agent =
        agent
        |> ThreadAgent.ensure(id: "thread-for-agent-1")
        |> ThreadAgent.append(%{kind: :message, payload: %{content: "hello"}})

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "thread-test-1")

      assert thawed.state[:__thread__] != nil
      assert thawed.state[:__thread__].id == "thread-for-agent-1"
    end

    test "thread rev matches entry count" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "thread-test-2")

      thread =
        Thread.new(id: "thread-rev-test")
        |> Thread.append(%{kind: :message, payload: %{content: "one"}})
        |> Thread.append(%{kind: :message, payload: %{content: "two"}})
        |> Thread.append(%{kind: :message, payload: %{content: "three"}})

      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "thread-test-2")

      rehydrated = thawed.state[:__thread__]
      assert rehydrated.rev == 3
      assert Thread.entry_count(rehydrated) == 3
    end

    test "entry seq numbers are correct and ordered" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "thread-test-3")

      entries = [
        %{kind: :user_message, payload: %{role: "user", content: "query"}},
        %{kind: :tool_call, payload: %{name: "search", args: %{q: "test"}}},
        %{kind: :tool_result, payload: %{result: "found 5 results"}},
        %{kind: :assistant_message, payload: %{role: "assistant", content: "response"}}
      ]

      thread = Thread.new(id: "seq-test-thread") |> Thread.append(entries)
      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "thread-test-3")

      rehydrated = thawed.state[:__thread__]
      entry_list = Thread.to_list(rehydrated)

      assert length(entry_list) == 4
      assert Enum.at(entry_list, 0).seq == 0
      assert Enum.at(entry_list, 1).seq == 1
      assert Enum.at(entry_list, 2).seq == 2
      assert Enum.at(entry_list, 3).seq == 3
    end

    test "entry payloads are preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "thread-test-4")

      thread =
        Thread.new(id: "payload-test-thread")
        |> Thread.append(%{
          kind: :message,
          payload: %{complex: %{nested: "data"}, list: [1, 2, 3]}
        })

      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "thread-test-4")

      rehydrated = thawed.state[:__thread__]
      [entry] = Thread.to_list(rehydrated)

      assert entry.payload.complex == %{nested: "data"}
      assert entry.payload.list == [1, 2, 3]
    end
  end

  describe "state mutations: create → modify state → hibernate → thaw → verify state" do
    test "modified step value is preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "state-mut-1")
      agent = %{agent | state: %{agent.state | step: 5}}

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "state-mut-1")

      assert thawed.state.step == 5
    end

    test "modified status value is preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "state-mut-2")
      agent = %{agent | state: %{agent.state | status: :completed}}

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "state-mut-2")

      assert thawed.state.status == :completed
    end

    test "modified data map is preserved" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "state-mut-3")
      agent = %{agent | state: %{agent.state | data: %{user_id: "u123", items: ["a", "b", "c"]}}}

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "state-mut-3")

      assert thawed.state.data == %{user_id: "u123", items: ["a", "b", "c"]}
    end

    test "all state fields are preserved together" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "state-mut-4")

      agent = %{
        agent
        | state: %{
            agent.state
            | step: 10,
              status: :in_progress,
              data: %{key: "value", count: 42}
          }
      }

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "state-mut-4")

      assert thawed.state.step == 10
      assert thawed.state.status == :in_progress
      assert thawed.state.data == %{key: "value", count: 42}
    end
  end

  describe "multiple agents: hibernate/thaw multiple agents with different IDs" do
    test "multiple agents can be hibernated and thawed independently" do
      jido = create_jido_instance(unique_table())

      agent1 = WorkflowAgent.new(id: "multi-agent-1")
      agent1 = %{agent1 | state: %{agent1.state | step: 1, status: :first}}

      agent2 = WorkflowAgent.new(id: "multi-agent-2")
      agent2 = %{agent2 | state: %{agent2.state | step: 2, status: :second}}

      agent3 = WorkflowAgent.new(id: "multi-agent-3")
      agent3 = %{agent3 | state: %{agent3.state | step: 3, status: :third}}

      :ok = Jido.Persist.hibernate(jido, agent1)
      :ok = Jido.Persist.hibernate(jido, agent2)
      :ok = Jido.Persist.hibernate(jido, agent3)

      {:ok, thawed1} = Jido.Persist.thaw(jido, Jido.Agent, "multi-agent-1")
      {:ok, thawed2} = Jido.Persist.thaw(jido, Jido.Agent, "multi-agent-2")
      {:ok, thawed3} = Jido.Persist.thaw(jido, Jido.Agent, "multi-agent-3")

      assert thawed1.id == "multi-agent-1"
      assert thawed1.state.step == 1
      assert thawed1.state.status == :first

      assert thawed2.id == "multi-agent-2"
      assert thawed2.state.step == 2
      assert thawed2.state.status == :second

      assert thawed3.id == "multi-agent-3"
      assert thawed3.state.step == 3
      assert thawed3.state.status == :third
    end

    test "multiple agents with threads can be hibernated and thawed independently" do
      jido = create_jido_instance(unique_table())

      agent1 = WorkflowAgent.new(id: "multi-thread-1")

      thread1 =
        Thread.new(id: "thread-multi-1")
        |> Thread.append(%{kind: :note, payload: %{text: "agent1"}})

      agent1 = ThreadAgent.put(agent1, thread1)

      agent2 = WorkflowAgent.new(id: "multi-thread-2")

      thread2 =
        Thread.new(id: "thread-multi-2")
        |> Thread.append(%{kind: :note, payload: %{text: "agent2"}})

      agent2 = ThreadAgent.put(agent2, thread2)

      :ok = Jido.Persist.hibernate(jido, agent1)
      :ok = Jido.Persist.hibernate(jido, agent2)

      {:ok, thawed1} = Jido.Persist.thaw(jido, Jido.Agent, "multi-thread-1")
      {:ok, thawed2} = Jido.Persist.thaw(jido, Jido.Agent, "multi-thread-2")

      assert thawed1.state[:__thread__].id == "thread-multi-1"
      assert thawed2.state[:__thread__].id == "thread-multi-2"

      [entry1] = Thread.to_list(thawed1.state[:__thread__])
      [entry2] = Thread.to_list(thawed2.state[:__thread__])

      assert entry1.payload.text == "agent1"
      assert entry2.payload.text == "agent2"
    end

    test "thawing nonexistent agent returns :not_found" do
      jido = create_jido_instance(unique_table())

      agent = WorkflowAgent.new(id: "exists")
      :ok = Jido.Persist.hibernate(jido, agent)

      assert :not_found = Jido.Persist.thaw(jido, Jido.Agent, "does-not-exist")
    end
  end

  describe "overwrite checkpoint: hibernate → modify → hibernate again → thaw → verify latest state" do
    test "second hibernate overwrites first checkpoint" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "overwrite-1")

      agent_v1 = %{agent | state: %{agent.state | step: 1, status: :version1}}
      :ok = Jido.Persist.hibernate(jido, agent_v1)

      agent_v2 = %{agent | state: %{agent.state | step: 2, status: :version2}}
      :ok = Jido.Persist.hibernate(jido, agent_v2)

      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "overwrite-1")

      assert thawed.state.step == 2
      assert thawed.state.status == :version2
    end

    test "thaw → modify → hibernate → thaw preserves modifications" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "overwrite-2")
      agent = %{agent | state: %{agent.state | step: 1}}

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed1} = Jido.Persist.thaw(jido, Jido.Agent, "overwrite-2")

      assert thawed1.state.step == 1

      updated = %{thawed1 | state: %{thawed1.state | step: 99, status: :final}}
      :ok = Jido.Persist.hibernate(jido, updated)

      {:ok, thawed2} = Jido.Persist.thaw(jido, Jido.Agent, "overwrite-2")

      assert thawed2.state.step == 99
      assert thawed2.state.status == :final
    end

    test "thread updates are preserved on re-hibernate" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "overwrite-3")

      thread = Thread.new(id: "overwrite-thread")
      thread = Thread.append(thread, %{kind: :message, payload: %{content: "first"}})
      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)

      {:ok, thawed1} = Jido.Persist.thaw(jido, Jido.Agent, "overwrite-3")
      assert Thread.entry_count(thawed1.state[:__thread__]) == 1

      updated_thread =
        Thread.new(id: "overwrite-thread-v2")
        |> Thread.append(%{kind: :message, payload: %{content: "new first"}})
        |> Thread.append(%{kind: :message, payload: %{content: "new second"}})

      updated = ThreadAgent.put(thawed1, updated_thread)
      :ok = Jido.Persist.hibernate(jido, updated)

      {:ok, thawed2} = Jido.Persist.thaw(jido, Jido.Agent, "overwrite-3")

      assert thawed2.state[:__thread__].id == "overwrite-thread-v2"
      assert Thread.entry_count(thawed2.state[:__thread__]) == 2
      assert thawed2.state[:__thread__].rev == 2
    end
  end

  describe "integration invariants" do
    test "checkpoint never contains full Thread struct, only pointer" do
      table = unique_table()
      jido = create_jido_instance(table)
      agent = WorkflowAgent.new(id: "invariant-1")

      thread =
        Thread.new(id: "invariant-thread")
        |> Thread.append(%{kind: :message, payload: %{content: "test"}})

      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)

      {:ok, checkpoint} = ETS.get_checkpoint({Jido.Agent, "invariant-1"}, table: table)

      refute is_struct(checkpoint.thread, Thread)
      assert checkpoint.thread == %{id: "invariant-thread", rev: 1}
      refute Map.has_key?(checkpoint.state, :__thread__)
    end

    test "agent.id is preserved exactly" do
      jido = create_jido_instance(unique_table())
      original_id = "exact-id-preservation-test-#{System.unique_integer([:positive])}"
      agent = WorkflowAgent.new(id: original_id)

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, original_id)

      assert thawed.id == original_id
    end

    test "thread entries preserve kind field" do
      jido = create_jido_instance(unique_table())
      agent = WorkflowAgent.new(id: "kind-test")

      thread =
        Thread.new(id: "kind-test-thread")
        |> Thread.append(%{kind: :user_input, payload: %{}})
        |> Thread.append(%{kind: :system_response, payload: %{}})
        |> Thread.append(%{kind: :tool_call, payload: %{}})

      agent = ThreadAgent.put(agent, thread)

      :ok = Jido.Persist.hibernate(jido, agent)
      {:ok, thawed} = Jido.Persist.thaw(jido, Jido.Agent, "kind-test")

      entries = Thread.to_list(thawed.state[:__thread__])
      assert Enum.at(entries, 0).kind == :user_input
      assert Enum.at(entries, 1).kind == :system_response
      assert Enum.at(entries, 2).kind == :tool_call
    end
  end
end
