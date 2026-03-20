defmodule JidoTest.PersistTest do
  use JidoTest.Case, async: true

  alias Jido.Persist
  alias Jido.Scheduler
  alias Jido.Signal
  alias Jido.Storage.ETS
  alias Jido.Thread
  alias JidoTest.PersistTest.CustomAgent
  alias JidoTest.PersistTest.RuntimeStateCheckpointAgent
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

  defmodule RuntimeStateCheckpointAgent do
    use Jido.Agent,
      name: "runtime_state_checkpoint_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def checkpoint(agent, _ctx) do
      {:ok,
       %{
         version: 1,
         agent_module: __MODULE__,
         id: agent.id,
         state: %{
           value: agent.state.value,
           __thread__: %{runtime_only: true}
         },
         thread: nil
       }}
    end
  end

  defmodule RaisingCheckpointAgent do
    use Jido.Agent,
      name: "raising_checkpoint_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def checkpoint(_agent, _ctx) do
      raise "checkpoint boom"
    end
  end

  defmodule InvalidCheckpointStateAgent do
    use Jido.Agent,
      name: "invalid_checkpoint_state_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def checkpoint(agent, _ctx) do
      {:ok,
       %{
         version: 1,
         agent_module: __MODULE__,
         id: agent.id,
         state: [],
         thread: nil
       }}
    end
  end

  defmodule RaisingRestoreAgent do
    use Jido.Agent,
      name: "raising_restore_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def restore(_data, _ctx) do
      raise "restore boom"
    end
  end

  defmodule LenientRestoreAgent do
    use Jido.Agent,
      name: "lenient_restore_agent",
      schema: [value: [type: :string, default: ""]]

    @impl true
    def signal_routes(_ctx), do: []

    @impl true
    def restore(data, _ctx) do
      {:ok, new(id: data.id)}
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

    test "carries thread ref updates through checkpoint overlays" do
      table = unique_table()
      agent = TestAgent.new(id: "agent-ref-overlay")

      thread =
        Thread.new(id: "thread-ref-overlay")
        |> Thread.append(%{kind: :message, payload: %{content: "hello"}, refs: %{source: :seed}})
        |> Thread.update_entry_refs(0, %{slack_ts: "1234"})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({TestAgent, "agent-ref-overlay"}, table: table)

      assert checkpoint.thread == %{id: "thread-ref-overlay", rev: 1}

      assert checkpoint.__thread_overlay__ == %{
               ref_updates: %{0 => %{slack_ts: "1234"}},
               updated_at: thread.updated_at
             }
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

    test "custom checkpoints receive injected scheduler manifest" do
      table = unique_table()
      scheduler_key = Jido.Scheduler.cron_specs_state_key()

      agent = CustomAgent.new(id: "custom-cron-1")

      scheduler_manifest = %{
        durable: Jido.Scheduler.build_cron_spec("* * * * *", false, "America/New_York")
      }

      agent =
        %{agent | state: %{agent.state | value: "custom_value"}}
        |> then(fn agent ->
          %{agent | state: Map.put(agent.state, scheduler_key, scheduler_manifest)}
        end)

      assert :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({CustomAgent, "custom-cron-1"}, table: table)
      assert checkpoint.state[scheduler_key] == scheduler_manifest
    end

    test "returns structured error when checkpoint callback raises" do
      table = unique_table()
      agent = RaisingCheckpointAgent.new(id: "checkpoint-boom")

      assert {:error, {:checkpoint_callback_failed, {:raised, RuntimeError, "checkpoint boom"}}} =
               Persist.hibernate(storage(table), agent)

      assert :not_found =
               ETS.get_checkpoint({RaisingCheckpointAgent, "checkpoint-boom"}, table: table)
    end

    test "returns structured error for malformed checkpoint state" do
      table = unique_table()
      agent = InvalidCheckpointStateAgent.new(id: "invalid-checkpoint-state")

      assert {:error, {:invalid_checkpoint, {:invalid_state, []}}} =
               Persist.hibernate(storage(table), agent)

      assert :not_found =
               ETS.get_checkpoint({InvalidCheckpointStateAgent, "invalid-checkpoint-state"},
                 table: table
               )
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

    test "thaws agent with thread ref updates preserved across repeated hibernation" do
      table = unique_table()
      agent = TestAgent.new(id: "thaw-ref-updates")

      thread =
        Thread.new(id: "thaw-ref-thread")
        |> Thread.append(%{kind: :message, payload: %{content: "hello"}, refs: %{source: :seed}})
        |> Thread.update_entry_refs(0, %{slack_ts: "1234"})

      agent = %{agent | state: Map.put(agent.state, :__thread__, thread)}

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "thaw-ref-updates")

      rehydrated_thread = thawed.state[:__thread__]
      assert Thread.get_entry(rehydrated_thread, 0).refs == %{source: :seed, slack_ts: "1234"}
      assert rehydrated_thread.updated_at == thread.updated_at

      :ok = Persist.hibernate(storage(table), thawed)
      assert {:ok, thawed_again} = Persist.thaw(storage(table), TestAgent, "thaw-ref-updates")

      assert Thread.get_entry(thawed_again.state[:__thread__], 0).refs == %{
               source: :seed,
               slack_ts: "1234"
             }
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

    test "returns structured error when restore callback raises" do
      table = unique_table()

      checkpoint = %{
        version: 1,
        agent_module: RaisingRestoreAgent,
        id: "restore-boom",
        state: %{},
        thread: nil
      }

      :ok = ETS.put_checkpoint({RaisingRestoreAgent, "restore-boom"}, checkpoint, table: table)

      assert {:error, {:restore_callback_failed, {:raised, RuntimeError, "restore boom"}}} =
               Persist.thaw(storage(table), RaisingRestoreAgent, "restore-boom")
    end

    test "returns structured error for malformed checkpoint state before restore" do
      table = unique_table()

      checkpoint = %{
        version: 1,
        agent_module: LenientRestoreAgent,
        id: "invalid-thaw-state",
        state: [],
        thread: nil
      }

      :ok =
        ETS.put_checkpoint({LenientRestoreAgent, "invalid-thaw-state"}, checkpoint, table: table)

      assert {:error, {:invalid_checkpoint, {:invalid_state, []}}} =
               Persist.thaw(storage(table), LenientRestoreAgent, "invalid-thaw-state")
    end

    test "preserves falsey scheduler manifest values across thaw" do
      table = unique_table()
      scheduler_key = Jido.Scheduler.cron_specs_state_key()

      scheduler_manifest = %{
        durable: Jido.Scheduler.build_cron_spec("* * * * *", false, "America/New_York")
      }

      agent =
        TestAgent.new(id: "thaw-falsey-cron")
        |> then(fn agent ->
          %{agent | state: Map.put(agent.state, scheduler_key, scheduler_manifest)}
        end)

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "thaw-falsey-cron")
      assert thawed.state[scheduler_key] == scheduler_manifest
      assert thawed.state[scheduler_key][:durable].message == false
    end

    test "preserves durable signal scheduler manifests across thaw" do
      table = unique_table()
      scheduler_key = Jido.Scheduler.cron_specs_state_key()

      signal =
        Signal.new!(%{
          type: "cron.tick",
          source: "/persist",
          data: %{count: 1}
        })

      scheduler_manifest = %{
        durable: Jido.Scheduler.build_cron_spec("* * * * *", signal, "America/New_York")
      }

      agent =
        TestAgent.new(id: "thaw-signal-cron")
        |> then(fn agent ->
          %{agent | state: Map.put(agent.state, scheduler_key, scheduler_manifest)}
        end)

      :ok = Persist.hibernate(storage(table), agent)

      assert {:ok, thawed} = Persist.thaw(storage(table), TestAgent, "thaw-signal-cron")
      assert thawed.state[scheduler_key] == scheduler_manifest
      assert thawed.state[scheduler_key][:durable].message == signal
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

  describe "persist_scheduler_manifest/5" do
    test "patches an existing checkpoint, strips runtime thread key, and updates scheduler manifest" do
      table = unique_table()
      checkpoint_key = {TestAgent, {:pool, "existing"}}
      scheduler_key = Scheduler.cron_specs_state_key()

      existing_checkpoint = %{
        version: 1,
        agent_module: TestAgent,
        id: "existing-id",
        state:
          %{
            counter: 7,
            status: :active,
            __thread__: %{runtime_only: true}
          }
          |> Map.put(scheduler_key, %{legacy: :value}),
        thread: nil
      }

      :ok = ETS.put_checkpoint(checkpoint_key, existing_checkpoint, table: table)

      manifest = %{
        durable_job: Scheduler.build_cron_spec("* * * * *", :tick, "Etc/UTC")
      }

      agent = TestAgent.new(id: "existing-id")

      assert :ok =
               Persist.persist_scheduler_manifest(
                 storage(table),
                 TestAgent,
                 {:pool, "existing"},
                 agent,
                 manifest
               )

      {:ok, updated_checkpoint} = ETS.get_checkpoint(checkpoint_key, table: table)
      refute Map.has_key?(updated_checkpoint.state, :__thread__)
      assert updated_checkpoint.state.counter == 7
      assert updated_checkpoint.state.status == :active
      assert updated_checkpoint.state[scheduler_key] == manifest
    end

    test "falls back to full hibernate when checkpoint does not exist" do
      table = unique_table()
      checkpoint_key = {TestAgent, {:pool, "missing"}}
      scheduler_key = Scheduler.cron_specs_state_key()

      manifest = %{
        first_job: Scheduler.build_cron_spec("@hourly", :tick, nil)
      }

      agent = TestAgent.new(id: "agent-missing")
      agent = %{agent | state: %{agent.state | counter: 42, status: :processing}}

      assert :ok =
               Persist.persist_scheduler_manifest(
                 storage(table),
                 TestAgent,
                 {:pool, "missing"},
                 agent,
                 manifest
               )

      {:ok, checkpoint} = ETS.get_checkpoint(checkpoint_key, table: table)
      assert checkpoint.state.counter == 42
      assert checkpoint.state.status == :processing
      assert checkpoint.state[scheduler_key] == manifest
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

    test "checkpoint with thread enforces invariants and injects scheduler manifest" do
      table = unique_table()
      scheduler_key = Jido.Scheduler.cron_specs_state_key()
      agent = CustomAgent.new(id: "custom-thread-1")
      agent = %{agent | state: %{agent.state | value: "with_thread"}}

      thread =
        Thread.new(id: "custom-thread")
        |> Thread.append(%{kind: :note, payload: %{text: "custom note"}})

      scheduler_manifest = %{
        durable: Jido.Scheduler.build_cron_spec("* * * * *", :tick, nil)
      }

      agent =
        %{agent | state: Map.put(agent.state, :__thread__, thread)}
        |> then(fn agent ->
          %{agent | state: Map.put(agent.state, scheduler_key, scheduler_manifest)}
        end)

      :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} = ETS.get_checkpoint({CustomAgent, "custom-thread-1"}, table: table)

      assert checkpoint.thread == %{id: "custom-thread", rev: 1}
      refute Map.has_key?(checkpoint.state || %{}, :__thread__)
      assert checkpoint.state[scheduler_key] == scheduler_manifest
    end

    test "custom checkpoint state always strips __thread__ and preserves scheduler manifest invariants" do
      table = unique_table()
      scheduler_key = Scheduler.cron_specs_state_key()

      manifest = %{
        invariant_job: Scheduler.build_cron_spec("*/5 * * * *", :tick, nil)
      }

      agent = RuntimeStateCheckpointAgent.new(id: "runtime-invariant-1")

      agent =
        %{
          agent
          | state:
              agent.state |> Map.put(:value, "with_runtime") |> Map.put(scheduler_key, manifest)
        }

      :ok = Persist.hibernate(storage(table), agent)

      {:ok, checkpoint} =
        ETS.get_checkpoint({RuntimeStateCheckpointAgent, "runtime-invariant-1"}, table: table)

      refute Map.has_key?(checkpoint.state || %{}, :__thread__)
      assert checkpoint.state[scheduler_key] == manifest
    end
  end
end
