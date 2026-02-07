defmodule JidoTest.Thread.StrategyIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.FSM, as: StrategyFSM
  alias Jido.Thread
  alias Jido.Thread.Agent, as: ThreadAgent

  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{executed: true}}
  end

  defmodule ValueAction do
    @moduledoc false
    use Jido.Action,
      name: "value_action",
      schema: [value: [type: :integer, required: true]]

    def run(%{value: value}, _context), do: {:ok, %{value: value}}
  end

  defmodule FailingAction do
    @moduledoc false
    use Jido.Action,
      name: "failing_action",
      schema: []

    def run(_params, _context), do: {:error, "intentional failure"}
  end

  defmodule DirectTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "direct_test_agent",
      strategy: Jido.Agent.Strategy.Direct,
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  defmodule DirectThreadAgent do
    @moduledoc false
    use Jido.Agent,
      name: "direct_thread_agent",
      strategy: {Jido.Agent.Strategy.Direct, thread?: true},
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  defmodule FSMTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "fsm_test_agent",
      strategy: StrategyFSM,
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  defmodule FSMThreadAgent do
    @moduledoc false
    use Jido.Agent,
      name: "fsm_thread_agent",
      strategy: {StrategyFSM, thread?: true},
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  describe "Direct strategy without thread?" do
    test "behavior unchanged, no thread created" do
      agent = DirectTestAgent.new()
      {updated, directives} = DirectTestAgent.cmd(agent, SimpleAction)

      assert updated.state.executed == true
      assert directives == []
      refute ThreadAgent.has_thread?(updated)
    end

    test "multiple actions execute without thread" do
      agent = DirectTestAgent.new()

      {updated, _} =
        DirectTestAgent.cmd(agent, [
          SimpleAction,
          {ValueAction, %{value: 42}}
        ])

      assert updated.state.executed == true
      assert updated.state.value == 42
      refute ThreadAgent.has_thread?(updated)
    end
  end

  describe "Direct strategy with thread?: true" do
    test "creates thread and appends instruction_start/end entries" do
      agent = DirectThreadAgent.new()
      {updated, directives} = DirectThreadAgent.cmd(agent, SimpleAction)

      assert updated.state.executed == true
      assert directives == []
      assert ThreadAgent.has_thread?(updated)

      thread = ThreadAgent.get(updated)
      assert Thread.entry_count(thread) == 2

      entries = Thread.to_list(thread)
      [start_entry, end_entry] = entries

      assert start_entry.kind == :instruction_start
      assert start_entry.payload.action == SimpleAction

      assert end_entry.kind == :instruction_end
      assert end_entry.payload.action == SimpleAction
      assert end_entry.payload.status == :ok
    end

    test "tracks param keys but not values" do
      agent = DirectThreadAgent.new()
      {updated, _} = DirectThreadAgent.cmd(agent, {ValueAction, %{value: 42}})

      thread = ThreadAgent.get(updated)
      [start_entry, _end_entry] = Thread.to_list(thread)

      assert start_entry.payload.action == ValueAction
      assert :value in start_entry.payload.param_keys
      refute Map.has_key?(start_entry.payload, :value)
    end

    test "records :error status on failing action" do
      agent = DirectThreadAgent.new()
      {updated, directives} = DirectThreadAgent.cmd(agent, FailingAction)

      assert [%Jido.Agent.Directive.Error{}] = directives

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)
      end_entry = List.last(entries)

      assert end_entry.kind == :instruction_end
      assert end_entry.payload.status == :error
    end

    test "tracks multiple instructions in sequence" do
      agent = DirectThreadAgent.new()

      {updated, _} =
        DirectThreadAgent.cmd(agent, [SimpleAction, {ValueAction, %{value: 100}}])

      thread = ThreadAgent.get(updated)
      assert Thread.entry_count(thread) == 4

      entries = Thread.to_list(thread)
      kinds = Enum.map(entries, & &1.kind)
      assert kinds == [:instruction_start, :instruction_end, :instruction_start, :instruction_end]
    end

    test "continues tracking when thread already exists" do
      agent = DirectTestAgent.new()
      agent = ThreadAgent.ensure(agent)
      agent = ThreadAgent.append(agent, %{kind: :note, payload: %{text: "existing"}})

      {updated, _} = DirectTestAgent.cmd(agent, SimpleAction)

      thread = ThreadAgent.get(updated)
      assert Thread.entry_count(thread) == 3

      entries = Thread.to_list(thread)
      assert hd(entries).kind == :note
    end
  end

  describe "FSM strategy without thread?" do
    test "behavior unchanged, no thread created" do
      agent = FSMTestAgent.new()
      {updated, directives} = FSMTestAgent.cmd(agent, SimpleAction)

      assert updated.state.executed == true
      assert directives == []
      refute ThreadAgent.has_thread?(updated)
    end

    test "multiple actions execute without thread" do
      agent = FSMTestAgent.new()

      {updated, _} =
        FSMTestAgent.cmd(agent, [
          SimpleAction,
          {ValueAction, %{value: 42}}
        ])

      assert updated.state.executed == true
      assert updated.state.value == 42
      refute ThreadAgent.has_thread?(updated)
    end
  end

  describe "FSM strategy with thread?: true" do
    test "creates thread and appends checkpoint entries for transitions" do
      agent = FSMThreadAgent.new()
      {updated, directives} = FSMThreadAgent.cmd(agent, SimpleAction)

      assert updated.state.executed == true
      assert directives == []
      assert ThreadAgent.has_thread?(updated)

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)

      checkpoint_entries = Enum.filter(entries, &(&1.kind == :checkpoint))

      # init checkpoint + 2 transition checkpoints
      assert length(checkpoint_entries) == 3

      [init_checkpoint | transition_checkpoints] = checkpoint_entries
      assert init_checkpoint.payload.event == :init
      assert init_checkpoint.payload.fsm_state == "idle"

      [processing_checkpoint, idle_checkpoint] = transition_checkpoints
      assert processing_checkpoint.payload.event == :transition
      assert processing_checkpoint.payload.fsm_state == "processing"

      assert idle_checkpoint.payload.event == :transition
      assert idle_checkpoint.payload.fsm_state == "idle"
    end

    test "tracks instruction_start/end entries alongside checkpoints" do
      agent = FSMThreadAgent.new()
      {updated, _} = FSMThreadAgent.cmd(agent, SimpleAction)

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)

      kinds = Enum.map(entries, & &1.kind)
      assert :checkpoint in kinds
      assert :instruction_start in kinds
      assert :instruction_end in kinds
    end

    test "records :error status on failing action" do
      agent = FSMThreadAgent.new()
      {updated, directives} = FSMThreadAgent.cmd(agent, FailingAction)

      assert [%Jido.Agent.Directive.Error{}] = directives

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)

      instruction_end = Enum.find(entries, &(&1.kind == :instruction_end))
      assert instruction_end.payload.status == :error
    end

    test "tracks multiple instructions with checkpoints" do
      agent = FSMThreadAgent.new()

      {updated, _} =
        FSMThreadAgent.cmd(agent, [SimpleAction, {ValueAction, %{value: 100}}])

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)

      checkpoint_count = Enum.count(entries, &(&1.kind == :checkpoint))
      instruction_start_count = Enum.count(entries, &(&1.kind == :instruction_start))
      instruction_end_count = Enum.count(entries, &(&1.kind == :instruction_end))

      # 1 init + 2 transitions
      assert checkpoint_count == 3
      assert instruction_start_count == 2
      assert instruction_end_count == 2
    end

    test "continues tracking when thread already exists" do
      agent = FSMTestAgent.new()
      agent = ThreadAgent.ensure(agent)
      agent = ThreadAgent.append(agent, %{kind: :note, payload: %{text: "existing"}})

      {updated, _} = FSMTestAgent.cmd(agent, SimpleAction)

      thread = ThreadAgent.get(updated)
      entries = Thread.to_list(thread)

      assert hd(entries).kind == :note
      assert Thread.entry_count(thread) > 1
    end
  end

  describe "FSM init with thread?" do
    test "appends checkpoint entry on init when thread? enabled" do
      {:ok, agent} = Agent.new(%{id: "test"})

      ctx = %{
        agent_module: FSMTestAgent,
        strategy_opts: [thread?: true, initial_state: "idle"]
      }

      {agent, _directives} = StrategyFSM.init(agent, ctx)

      assert ThreadAgent.has_thread?(agent)
      thread = ThreadAgent.get(agent)
      entries = Thread.to_list(thread)

      assert length(entries) == 1
      [checkpoint] = entries
      assert checkpoint.kind == :checkpoint
      assert checkpoint.payload.event == :init
      assert checkpoint.payload.fsm_state == "idle"
    end

    test "no checkpoint when thread? not enabled" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: FSMTestAgent, strategy_opts: []}

      {agent, _directives} = StrategyFSM.init(agent, ctx)

      refute ThreadAgent.has_thread?(agent)
    end
  end
end
