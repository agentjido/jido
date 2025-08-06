defmodule Jido.Actions.IteratorTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.{Iterator, CounterBody, LimitDecision}

  # Simple test action for body testing
  defmodule TestBodyAction do
    use Jido.Action, name: "test_body"

    def run(params, _context) do
      step = params[:step] || 0
      iterator_state = params[:iterator_state] || %{}
      
      result = %{
        step: step,
        test_value: (iterator_state[:test_value] || 0) + 1
      }
      
      {:ok, result}
    end
  end

  # Simple test action for decision testing
  defmodule TestDecisionAction do
    use Jido.Action, name: "test_decision"

    def run(params, _context) do
      step = params[:step] || 0
      iterator_state = params[:iterator_state] || %{}
      test_value = iterator_state[:test_value] || 0
      
      # Stop when test_value reaches 3
      continue = test_value < 3 and step < 10
      
      {:ok, %{continue: continue, test_value: test_value}}
    end
  end

  describe "Iterator action - basic functionality" do
    test "terminates immediately when step >= max_steps" do
      params = %{
        step: 10,
        max_steps: 10,
        body_action: TestBodyAction,
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.step == 10
      assert result.max_steps == 10
      assert result.completed == true
      assert result.termination_reason == :max_steps_reached
      assert result.message =~ "maximum steps (10) reached"
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end

    test "requires body_action parameter" do
      params = %{step: 0, max_steps: 10, state_path: [:iterator_state]}
      context = %{state: %{}}

      # Should handle missing body_action gracefully
      assert {:ok, result, directive} = Iterator.run(params, context)
      assert result.completed == true
      assert result.termination_reason == :body_action_error
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end
  end

  describe "Iterator action - body action execution" do
    test "executes body action and accumulates state" do
      run_id = "test_run_123"
      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        state_path: [:iterator_state],
        run_id: run_id
      }

      # Pre-populate state with initial data
      context = %{state: %{iterator_state: %{run_id => %{test_value: 5}}}}

      assert {:ok, result, directives} = Iterator.run(params, context)

      assert result.step == 0
      assert result.completed == false
      assert result.state.test_value == 6  # Body action incremented it
      assert result.state.steps_completed == [0]
      assert result.body_result.test_value == 6

      # Should return list of directives: state update and enqueue
      assert is_list(directives)
      assert length(directives) == 2
      
      [state_directive, enqueue_directive] = directives
      
      # Check state directive
      assert %Jido.Agent.Directive.StateModification{} = state_directive
      assert state_directive.op == :set
      assert state_directive.path == [:iterator_state, run_id]
      
      # Check enqueue directive
      assert %Jido.Agent.Directive.Enqueue{} = enqueue_directive
      assert enqueue_directive.action == Jido.Actions.Iterator
      assert enqueue_directive.params.step == 1
      assert enqueue_directive.params.body_action == TestBodyAction
      assert enqueue_directive.params.state_path == [:iterator_state]
    end

    test "handles body action errors gracefully" do
      # Create a body action that will fail
      defmodule FailingBodyAction do
        use Jido.Action, name: "failing_body"
        def run(_params, _context), do: {:error, "deliberate failure"}
      end

      params = %{
        step: 0,
        max_steps: 10,
        body_action: FailingBodyAction,
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.completed == true
      assert result.termination_reason == :body_action_error
      assert result.error == "deliberate failure"
      assert result.message =~ "body action error at step 0"
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end
  end

  describe "Iterator action - decision action control" do
    test "uses decision action to control iteration flow" do
      run_id = "test_decision_123"
      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        decision_action: TestDecisionAction,
        state_path: [:iterator_state],
        run_id: run_id
      }

      # Pre-populate state - this will become 3 after body execution, triggering stop
      context = %{state: %{iterator_state: %{run_id => %{test_value: 2}}}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.step == 0
      assert result.completed == true
      assert result.termination_reason == :decision_action_stopped
      assert result.state.test_value == 3
      assert result.message =~ "Iterator completed after 1 steps"
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end

    test "continues iteration when decision action returns true" do
      run_id = "test_continue_123"
      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        decision_action: TestDecisionAction,
        state_path: [:iterator_state],
        run_id: run_id
      }

      # Pre-populate state - will become 1, which is < 3, so should continue
      context = %{state: %{iterator_state: %{run_id => %{test_value: 0}}}}

      assert {:ok, result, directives} = Iterator.run(params, context)

      assert result.step == 0
      assert result.completed == false
      assert result.state.test_value == 1

      # Should have list of directives
      assert is_list(directives)
      assert length(directives) == 2
      
      [_state_directive, enqueue_directive] = directives
      assert %Jido.Agent.Directive.Enqueue{} = enqueue_directive
      assert enqueue_directive.params.step == 1
    end

    test "falls back to step limit when no decision action provided" do
      params = %{
        step: 8,
        max_steps: 10,
        body_action: TestBodyAction,
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, directives} = Iterator.run(params, context)

      assert result.completed == false
      assert is_list(directives)
      
      # Should have path creation directive, state directive, and enqueue directive
      assert length(directives) >= 2
      enqueue_directive = List.last(directives)
      assert %Jido.Agent.Directive.Enqueue{} = enqueue_directive
      assert enqueue_directive.params.step == 9
    end
  end

  describe "Iterator action - with CounterBody and LimitDecision" do
    test "works with CounterBody action" do
      run_id = "test_counter_123"
      params = %{
        step: 0,
        max_steps: 10,
        body_action: CounterBody,
        body_params: %{increment: 5},
        state_path: [:iterator_state],
        run_id: run_id
      }

      context = %{state: %{iterator_state: %{run_id => %{count: 10}}}}

      assert {:ok, result, _directives} = Iterator.run(params, context)

      assert result.body_result.counter_history.new_count == 15
      assert result.state.count == 15
      assert result.state.steps_completed == [0]
    end

    test "works with LimitDecision action" do
      run_id = "test_limit_123"
      params = %{
        step: 0,
        max_steps: 100,
        body_action: CounterBody,
        body_params: %{increment: 10},
        decision_action: LimitDecision,
        decision_params: %{count_limit: 25},
        state_path: [:iterator_state],
        run_id: run_id
      }

      # Will become 30 after increment, exceeding limit
      context = %{state: %{iterator_state: %{run_id => %{count: 20}}}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.completed == true
      assert result.termination_reason == :decision_action_stopped
      assert result.state.count == 30
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end

    test "respects max_steps even with decision action" do
      run_id = "test_max_steps_123"
      params = %{
        step: 9,
        max_steps: 10,
        body_action: CounterBody,
        decision_action: LimitDecision,
        decision_params: %{count_limit: 1000},  # High limit
        state_path: [:iterator_state],
        run_id: run_id
      }

      context = %{state: %{iterator_state: %{run_id => %{count: 0}}}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.completed == true
      # Decision action would want to continue, but max_steps prevents it
      # Since decision action is present, it determines termination reason
      assert result.termination_reason == :decision_action_stopped
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end
  end

  describe "Iterator action - edge cases" do
    test "generates run_id when not provided" do
      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, _directives} = Iterator.run(params, context)

      assert is_binary(result.run_id)
      # IDs from Jido.Signal.ID.generate!() are longer than 16 characters
      assert String.length(result.run_id) > 16
    end

    test "preserves run_id across iterations" do
      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        run_id: "custom_run_id",
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, directives} = Iterator.run(params, context)

      assert result.run_id == "custom_run_id"
      
      # Check that run_id is preserved in enqueue directive
      assert is_list(directives)
      enqueue_directive = List.last(directives)
      assert %Jido.Agent.Directive.Enqueue{} = enqueue_directive
      assert enqueue_directive.params.run_id == "custom_run_id"
    end

    test "handles decision action errors by stopping iteration" do
      defmodule FailingDecisionAction do
        use Jido.Action, name: "failing_decision"
        def run(_params, _context), do: {:error, "decision failed"}
      end

      params = %{
        step: 0,
        max_steps: 10,
        body_action: TestBodyAction,
        decision_action: FailingDecisionAction,
        state_path: [:iterator_state]
      }

      context = %{state: %{}}

      assert {:ok, result, directive} = Iterator.run(params, context)

      assert result.completed == true
      assert result.termination_reason == :decision_action_stopped
      
      # Should have cleanup directive
      assert %Jido.Agent.Directive.StateModification{} = directive
      assert directive.op == :delete
    end
  end
end
