defmodule JidoTest.Agent.StrategyFSMTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Strategy.FSM
  alias Jido.Agent.Strategy.State, as: StratState

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

  defmodule EffectAction do
    @moduledoc false
    use Jido.Action,
      name: "effect_action",
      schema: []

    alias Jido.Agent.{Directive, StateOp}

    def run(_params, _context) do
      effects = [
        %StateOp.SetState{attrs: %{extra: "data"}},
        Directive.emit(%{type: "test.event"})
      ]

      {:ok, %{primary: "result"}, effects}
    end
  end

  defmodule SetPathAction do
    @moduledoc false
    use Jido.Action,
      name: "set_path_action",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:nested, :value], value: 42}}
    end
  end

  defmodule DeletePathAction do
    @moduledoc false
    use Jido.Action,
      name: "delete_path_action",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:ok, %{}, %StateOp.DeletePath{path: [:to_remove, :nested]}}
    end
  end

  defmodule FSMTestAgent do
    @moduledoc false
    use Jido.Agent,
      name: "fsm_test_agent",
      strategy: Jido.Agent.Strategy.FSM,
      schema: [value: [type: :integer, default: 0]]

    def signal_routes(_ctx), do: []
  end

  defmodule CustomFSMAgent do
    @moduledoc false
    use Jido.Agent,
      name: "custom_fsm_agent",
      strategy:
        {Jido.Agent.Strategy.FSM,
         initial_state: "ready",
         transitions: %{
           "ready" => ["working"],
           "working" => ["ready", "done"],
           "done" => ["ready"]
         }},
      schema: []

    def signal_routes(_ctx), do: []
  end

  defmodule NoAutoTransitionAgent do
    @moduledoc false
    use Jido.Agent,
      name: "no_auto_transition_agent",
      strategy:
        {Jido.Agent.Strategy.FSM,
         initial_state: "idle",
         auto_transition: false,
         transitions: %{
           "idle" => ["processing"],
           "processing" => ["idle", "completed"]
         }},
      schema: []

    def signal_routes(_ctx), do: []
  end

  describe "FSM.Machine" do
    test "new/2 creates machine with initial state and transitions" do
      transitions = %{"a" => ["b"], "b" => ["a"]}
      machine = FSM.Machine.new("a", transitions)

      assert machine.status == "a"
      assert machine.transitions == transitions
      assert machine.processed_count == 0
      assert machine.last_result == nil
      assert machine.error == nil
    end

    test "transition/2 allows valid transitions" do
      transitions = %{"idle" => ["processing"], "processing" => ["idle"]}
      machine = FSM.Machine.new("idle", transitions)

      assert {:ok, machine} = FSM.Machine.transition(machine, "processing")
      assert machine.status == "processing"

      assert {:ok, machine} = FSM.Machine.transition(machine, "idle")
      assert machine.status == "idle"
    end

    test "transition/2 rejects invalid transitions" do
      transitions = %{"idle" => ["processing"], "processing" => ["idle"]}
      machine = FSM.Machine.new("idle", transitions)

      assert {:error, %Jido.Error.ExecutionError{} = err} =
               FSM.Machine.transition(machine, "completed")

      assert err.message == "FSM invalid transition"
      assert err.details.from == "idle"
      assert err.details.to == "completed"
    end
  end

  describe "init/2" do
    test "initializes with default transitions" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: FSMTestAgent, strategy_opts: []}

      {agent, directives} = FSM.init(agent, ctx)

      assert directives == []
      state = StratState.get(agent)
      assert state.module == FSM
      assert state.machine.status == "idle"
      assert state.initial_state == "idle"
      assert state.auto_transition == true
    end

    test "initializes with custom transitions from strategy_opts" do
      {:ok, agent} = Agent.new(%{id: "test"})

      ctx = %{
        agent_module: CustomFSMAgent,
        strategy_opts: [
          initial_state: "ready",
          transitions: %{"ready" => ["working"], "working" => ["ready", "done"]}
        ]
      }

      {agent, _} = FSM.init(agent, ctx)

      state = StratState.get(agent)
      assert state.machine.status == "ready"
      assert state.initial_state == "ready"
    end

    test "respects auto_transition option" do
      {:ok, agent} = Agent.new(%{id: "test"})
      ctx = %{agent_module: NoAutoTransitionAgent, strategy_opts: [auto_transition: false]}

      {agent, _} = FSM.init(agent, ctx)

      state = StratState.get(agent)
      assert state.auto_transition == false
    end
  end

  describe "cmd/3 with default agent" do
    test "executes simple action" do
      agent = FSMTestAgent.new()
      {updated, directives} = FSMTestAgent.cmd(agent, SimpleAction)

      assert updated.state.executed == true
      assert directives == []
    end

    test "executes action with params" do
      agent = FSMTestAgent.new()
      {updated, _} = FSMTestAgent.cmd(agent, {ValueAction, %{value: 42}})

      assert updated.state.value == 42
    end

    test "executes multiple actions in sequence" do
      agent = FSMTestAgent.new()

      {updated, _} =
        FSMTestAgent.cmd(agent, [
          SimpleAction,
          {ValueAction, %{value: 100}}
        ])

      assert updated.state.executed == true
      assert updated.state.value == 100
    end

    test "tracks processed count" do
      agent = FSMTestAgent.new()

      {updated, _} =
        FSMTestAgent.cmd(agent, [
          SimpleAction,
          SimpleAction,
          SimpleAction
        ])

      state = StratState.get(updated)
      assert state.machine.processed_count == 3
    end

    test "returns to initial state after processing" do
      agent = FSMTestAgent.new()
      {updated, _} = FSMTestAgent.cmd(agent, SimpleAction)

      state = StratState.get(updated)
      assert state.machine.status == "idle"
    end
  end

  describe "cmd/3 with custom transitions agent" do
    test "uses custom initial state" do
      agent = CustomFSMAgent.new()
      state = StratState.get(agent)

      assert state.machine.status == "ready"
    end

    test "transitions through custom states" do
      agent = CustomFSMAgent.new()
      {updated, _} = CustomFSMAgent.cmd(agent, SimpleAction)

      state = StratState.get(updated)
      assert state.machine.status == "ready"
    end
  end

  describe "cmd/3 with auto_transition disabled" do
    test "stays in processing state after cmd" do
      agent = NoAutoTransitionAgent.new()
      {updated, _} = NoAutoTransitionAgent.cmd(agent, SimpleAction)

      state = StratState.get(updated)
      assert state.machine.status == "processing"
    end
  end

  describe "cmd/3 error handling" do
    test "returns error directive on action failure" do
      agent = FSMTestAgent.new()
      {_updated, directives} = FSMTestAgent.cmd(agent, FailingAction)

      assert [%Jido.Agent.Directive.Error{context: :instruction}] = directives
    end

    test "stores error in machine state" do
      agent = FSMTestAgent.new()
      {updated, _} = FSMTestAgent.cmd(agent, FailingAction)

      state = StratState.get(updated)
      assert state.machine.error != nil
      assert state.machine.error.message == "intentional failure"
    end
  end

  describe "cmd/3 with effects" do
    test "handles mixed internal effects and external directives" do
      agent = FSMTestAgent.new()
      {updated, directives} = FSMTestAgent.cmd(agent, EffectAction)

      assert updated.state.primary == "result"
      assert updated.state.extra == "data"

      assert [%Jido.Agent.Directive.Emit{signal: %{type: "test.event"}}] = directives
    end

    test "handles SetPath effect" do
      agent = FSMTestAgent.new()
      {updated, directives} = FSMTestAgent.cmd(agent, SetPathAction)

      assert updated.state.nested.value == 42
      assert directives == []
    end

    test "handles DeletePath effect" do
      agent = FSMTestAgent.new(state: %{to_remove: %{nested: "gone", keep: "here"}})
      {updated, directives} = FSMTestAgent.cmd(agent, DeletePathAction)

      refute Map.has_key?(updated.state.to_remove, :nested)
      assert updated.state.to_remove.keep == "here"
      assert directives == []
    end
  end

  describe "snapshot/2" do
    test "returns snapshot with idle status by default" do
      agent = FSMTestAgent.new()
      ctx = %{agent_module: FSMTestAgent, strategy_opts: []}

      snapshot = FSM.snapshot(agent, ctx)

      assert %Jido.Agent.Strategy.Snapshot{} = snapshot
      assert snapshot.status == :idle
      assert snapshot.done? == false
      assert snapshot.result == nil
      assert snapshot.details.processed_count == 0
      assert snapshot.details.fsm_state == "idle"
    end

    test "returns snapshot after processing" do
      agent = FSMTestAgent.new()
      {agent, _} = FSMTestAgent.cmd(agent, SimpleAction)
      ctx = %{agent_module: FSMTestAgent, strategy_opts: []}

      snapshot = FSM.snapshot(agent, ctx)

      assert snapshot.status == :idle
      assert snapshot.result == %{executed: true}
      assert snapshot.details.processed_count == 1
    end

    test "maps FSM states to strategy statuses" do
      {:ok, agent} = Agent.new(%{id: "test"})

      test_cases = [
        {"idle", :idle, false},
        {"processing", :running, false},
        {"completed", :success, true},
        {"failed", :failure, true}
      ]

      for {fsm_state, expected_status, expected_done} <- test_cases do
        machine = %FSM.Machine{status: fsm_state, processed_count: 0, transitions: %{}}
        agent = StratState.put(agent, %{machine: machine})
        ctx = %{agent_module: FSMTestAgent, strategy_opts: []}

        snapshot = FSM.snapshot(agent, ctx)

        assert snapshot.status == expected_status,
               "Expected #{fsm_state} to map to #{expected_status}"

        assert snapshot.done? == expected_done
      end
    end
  end

  describe "integration with module-based agent" do
    test "FSMTestAgent uses FSM strategy" do
      assert FSMTestAgent.strategy() == Jido.Agent.Strategy.FSM
    end

    test "CustomFSMAgent has custom strategy opts" do
      assert CustomFSMAgent.strategy() == Jido.Agent.Strategy.FSM
      opts = CustomFSMAgent.strategy_opts()
      assert opts[:initial_state] == "ready"
      assert is_map(opts[:transitions])
    end

    test "strategy_snapshot returns proper snapshot" do
      agent = FSMTestAgent.new()
      snapshot = FSMTestAgent.strategy_snapshot(agent)

      assert %Jido.Agent.Strategy.Snapshot{} = snapshot
      assert snapshot.status == :idle
    end
  end
end
