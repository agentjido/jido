defmodule JidoExampleTest.FSMAgentTest do
  @moduledoc """
  Example test demonstrating the FSM (Finite State Machine) strategy.

  This example shows:
  - How to define an agent with `strategy: Jido.Agent.Strategy.FSM`
  - How the FSM transitions through states (idle -> processing -> idle)
  - How to use `FSM.snapshot/2` to inspect FSM status
  - How multiple actions accumulate processed_count
  - How to configure custom transitions

  ## Usage

  Run with: mix test test/examples/fsm_agent_test.exs --include example

  ## Key Concepts

  The FSM strategy wraps action execution with state machine semantics:
  - Starts in "idle" state by default
  - Transitions to "processing" when running actions
  - Auto-transitions back to "idle" after processing (configurable)
  - Tracks processed_count and last_result in machine state

  ## Configuration Options

  - `:initial_state` - Starting FSM state (default: "idle")
  - `:transitions` - Map of valid state transitions
  - `:auto_transition` - Return to initial state after processing (default: true)
  """
  use JidoTest.Case, async: true

  alias Jido.Agent.Strategy.FSM

  @moduletag :example
  @moduletag timeout: 15_000

  # ===========================================================================
  # ACTIONS: Pure state transformations
  # ===========================================================================

  defmodule ProcessWorkAction do
    @moduledoc false
    use Jido.Action,
      name: "process_work",
      schema: [
        work_item: [type: :string, required: true]
      ]

    def run(%{work_item: item}, context) do
      items = Map.get(context.state, :processed_items, [])
      {:ok, %{processed_items: items ++ [item], last_item: item}}
    end
  end

  defmodule CompleteTaskAction do
    @moduledoc false
    use Jido.Action,
      name: "complete_task",
      schema: [
        task_id: [type: :integer, required: true]
      ]

    def run(%{task_id: task_id}, context) do
      completed = Map.get(context.state, :completed_tasks, [])
      {:ok, %{completed_tasks: completed ++ [task_id]}}
    end
  end

  defmodule IncrementCounter do
    @moduledoc false
    use Jido.Action,
      name: "increment_counter",
      schema: [
        amount: [type: :integer, default: 1]
      ]

    def run(%{amount: amount}, context) do
      current = Map.get(context.state, :counter, 0)
      {:ok, %{counter: current + amount}}
    end
  end

  # ===========================================================================
  # AGENTS: FSM-based agents
  # ===========================================================================

  defmodule SimpleFSMAgent do
    @moduledoc false
    use Jido.Agent,
      name: "simple_fsm_agent",
      description: "Basic FSM agent with default transitions",
      strategy: Jido.Agent.Strategy.FSM,
      schema: [
        processed_items: [type: {:list, :string}, default: []],
        last_item: [type: :string, default: nil],
        counter: [type: :integer, default: 0]
      ]
  end

  defmodule TaskFSMAgent do
    @moduledoc false
    use Jido.Agent,
      name: "task_fsm_agent",
      description: "FSM agent for task processing",
      strategy: Jido.Agent.Strategy.FSM,
      schema: [
        completed_tasks: [type: {:list, :integer}, default: []]
      ]
  end

  defmodule CustomTransitionAgent do
    @moduledoc false
    use Jido.Agent,
      name: "custom_transition_agent",
      description: "FSM agent with custom transitions",
      strategy:
        {Jido.Agent.Strategy.FSM,
         initial_state: "ready",
         transitions: %{
           "ready" => ["processing"],
           "processing" => ["ready", "done", "error"],
           "done" => ["ready"],
           "error" => ["ready"]
         }},
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  defmodule NoAutoTransitionAgent do
    @moduledoc false
    use Jido.Agent,
      name: "no_auto_transition_agent",
      description: "FSM agent that stays in processing state",
      strategy: {Jido.Agent.Strategy.FSM, auto_transition: false},
      schema: [
        counter: [type: :integer, default: 0]
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "FSM initial state" do
    test "FSM starts in idle state by default" do
      agent = SimpleFSMAgent.new()
      snapshot = FSM.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
      assert snapshot.details.processed_count == 0
      assert snapshot.details.fsm_state == "idle"
    end

    test "FSM with custom initial state starts in that state" do
      agent = CustomTransitionAgent.new()
      snapshot = FSM.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.details.fsm_state == "ready"
    end
  end

  describe "FSM state transitions" do
    test "running an action transitions through states and back to idle" do
      agent = SimpleFSMAgent.new()

      {agent, directives} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "task-1"}})

      assert directives == []
      assert agent.state.processed_items == ["task-1"]
      assert agent.state.last_item == "task-1"

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.status == :idle
      assert snapshot.details.fsm_state == "idle"
      assert snapshot.details.processed_count == 1
    end

    test "FSM without auto_transition stays in processing state" do
      agent = NoAutoTransitionAgent.new()

      {agent, _directives} = NoAutoTransitionAgent.cmd(agent, {IncrementCounter, %{amount: 5}})

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.status == :running
      assert snapshot.details.fsm_state == "processing"
    end

    test "custom transitions work correctly" do
      agent = CustomTransitionAgent.new()

      {agent, _directives} = CustomTransitionAgent.cmd(agent, {IncrementCounter, %{amount: 10}})

      assert agent.state.counter == 10

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.details.fsm_state == "ready"
      assert snapshot.details.processed_count == 1
    end
  end

  describe "FSM.snapshot/2" do
    test "snapshot returns status, done?, and details" do
      agent = SimpleFSMAgent.new()

      {agent, _} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "item-1"}})

      snapshot = FSM.snapshot(agent, %{})

      assert is_atom(snapshot.status)
      assert is_boolean(snapshot.done?)
      assert is_map(snapshot.details)
      assert Map.has_key?(snapshot.details, :processed_count)
      assert Map.has_key?(snapshot.details, :fsm_state)
    end

    test "snapshot tracks last_result" do
      agent = SimpleFSMAgent.new()

      {agent, _} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "my-work"}})

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.result == %{processed_items: ["my-work"], last_item: "my-work"}
    end
  end

  describe "multiple actions and processed_count" do
    test "multiple cmd/2 calls accumulate processed_count" do
      agent = SimpleFSMAgent.new()

      {agent, []} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "item-1"}})
      assert FSM.snapshot(agent, %{}).details.processed_count == 1

      {agent, []} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "item-2"}})
      assert FSM.snapshot(agent, %{}).details.processed_count == 2

      {agent, []} = SimpleFSMAgent.cmd(agent, {ProcessWorkAction, %{work_item: "item-3"}})
      assert FSM.snapshot(agent, %{}).details.processed_count == 3

      assert agent.state.processed_items == ["item-1", "item-2", "item-3"]
    end

    test "list of actions in single cmd/2 increments processed_count for each" do
      agent = TaskFSMAgent.new()

      {agent, directives} =
        TaskFSMAgent.cmd(agent, [
          {CompleteTaskAction, %{task_id: 1}},
          {CompleteTaskAction, %{task_id: 2}},
          {CompleteTaskAction, %{task_id: 3}}
        ])

      assert directives == []
      assert agent.state.completed_tasks == [1, 2, 3]

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.details.processed_count == 3
      assert snapshot.status == :idle
    end

    test "mixed actions with counter updates" do
      agent = SimpleFSMAgent.new()

      {agent, []} =
        SimpleFSMAgent.cmd(agent, [
          {IncrementCounter, %{amount: 10}},
          {ProcessWorkAction, %{work_item: "work-a"}},
          {IncrementCounter, %{amount: 5}},
          {ProcessWorkAction, %{work_item: "work-b"}}
        ])

      assert agent.state.counter == 15
      assert agent.state.processed_items == ["work-a", "work-b"]

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.details.processed_count == 4
    end
  end

  describe "FSM auto_transition behavior" do
    test "auto_transition: true returns FSM to initial state after processing" do
      agent = SimpleFSMAgent.new()

      {agent, _} = SimpleFSMAgent.cmd(agent, {IncrementCounter, %{amount: 1}})

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.details.fsm_state == "idle"
      assert snapshot.status == :idle
    end

    test "auto_transition: false keeps FSM in processing state" do
      agent = NoAutoTransitionAgent.new()

      {agent, _} = NoAutoTransitionAgent.cmd(agent, {IncrementCounter, %{amount: 1}})

      snapshot = FSM.snapshot(agent, %{})
      assert snapshot.details.fsm_state == "processing"
      assert snapshot.status == :running
    end
  end
end
