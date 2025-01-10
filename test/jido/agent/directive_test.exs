defmodule JidoTest.DirectiveTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.Agent.Directive

  alias Jido.Agent.Directive.{
    EnqueueDirective,
    RegisterActionDirective,
    DeregisterActionDirective
  }

  alias Jido.Runner.Result
  alias Jido.Instruction
  alias JidoTest.TestAgents.BasicAgent

  setup :verify_on_exit!

  describe "is_directive?/1" do
    test "returns true for valid directives" do
      assert Directive.is_directive?(%EnqueueDirective{action: :test})
      assert Directive.is_directive?(%RegisterActionDirective{action_module: TestModule})
      assert Directive.is_directive?(%DeregisterActionDirective{action_module: TestModule})
    end

    test "returns true for ok-tupled directives" do
      assert Directive.is_directive?({:ok, %EnqueueDirective{action: :test}})
      assert Directive.is_directive?({:ok, %RegisterActionDirective{action_module: TestModule}})
      assert Directive.is_directive?({:ok, %DeregisterActionDirective{action_module: TestModule}})
    end

    test "returns false for non-directives" do
      refute Directive.is_directive?(%{action: :test})
      refute Directive.is_directive?({:error, %EnqueueDirective{action: :test}})
      refute Directive.is_directive?(nil)
      refute Directive.is_directive?(:not_a_directive)
    end
  end

  describe "apply_agent_directives/3 queue management" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "removes current instruction before applying directives", %{agent: agent} do
      # First add an instruction to the queue
      initial_instruction = %Instruction{
        action: EnqueueAction,
        params: %{value: 1, amount: 5}
      }

      agent = %{
        agent
        | pending_instructions: :queue.in(initial_instruction, agent.pending_instructions)
      }

      # Create directive that should be applied after removing current instruction
      directive = %EnqueueDirective{
        action: Add,
        params: %{value: 1, amount: 5}
      }

      result = %Result{directives: [directive]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify queue state
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params == %{value: 1, amount: 5}
    end

    test "handles empty queue when applying directives", %{agent: agent} do
      directive = %EnqueueDirective{
        action: Add,
        params: %{value: 1}
      }

      result = %Result{directives: [directive]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == Add
    end

    test "maintains queue order when applying multiple directives", %{agent: agent} do
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 1}},
        %EnqueueDirective{action: Add, params: %{value: 2}},
        %EnqueueDirective{action: Add, params: %{value: 3}}
      ]

      result = %Result{directives: directives}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      assert :queue.len(updated_agent.pending_instructions) == 3

      # Check order of instructions
      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, q2} = :queue.out(q1)
      {{:value, third}, _} = :queue.out(q2)

      assert first.params.value == 1
      assert second.params.value == 2
      assert third.params.value == 3
    end

    test "handles complex queue transitions", %{agent: agent} do
      # Setup initial state with an EnqueueAction instruction
      initial_instruction = %Instruction{
        action: EnqueueAction,
        params: %{
          action: Add,
          params: %{value: 1, amount: 5}
        }
      }

      agent = %{
        agent
        | pending_instructions: :queue.in(initial_instruction, agent.pending_instructions)
      }

      # Apply multiple directives
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 2}},
        %EnqueueDirective{action: Add, params: %{value: 3}}
      ]

      result = %Result{directives: directives}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify final queue state
      assert :queue.len(updated_agent.pending_instructions) == 2

      {{:value, first}, q1} = :queue.out(updated_agent.pending_instructions)
      {{:value, second}, _} = :queue.out(q1)

      assert first.action == Add
      assert first.params.value == 2
      assert second.action == Add
      assert second.params.value == 3
    end

    test "preserves queue on directive failure", %{agent: agent} do
      # Add initial instruction
      initial_instruction = %Instruction{
        action: Add,
        params: %{value: 1}
      }

      agent = %{
        agent
        | pending_instructions: :queue.in(initial_instruction, agent.pending_instructions)
      }

      # Try to apply invalid directive
      bad_directive = %EnqueueDirective{action: nil}
      result = %Result{directives: [bad_directive]}

      {:error, :invalid_action} = Directive.apply_agent_directives(agent, result)

      # Verify original instruction is still in queue
      assert :queue.len(agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(agent.pending_instructions)
      assert instruction.action == Add
      assert instruction.params.value == 1
    end
  end

  describe "apply_agent_directives/3 edge cases" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "handles multiple queued instructions with directive application", %{agent: agent} do
      # Setup multiple initial instructions
      initial_instructions = [
        %Instruction{action: EnqueueAction, params: %{action: Add, value: 1}},
        %Instruction{action: EnqueueAction, params: %{action: Add, value: 2}}
      ]

      agent =
        Enum.reduce(initial_instructions, agent, fn inst, acc ->
          %{acc | pending_instructions: :queue.in(inst, acc.pending_instructions)}
        end)

      directive = %EnqueueDirective{action: Add, params: %{value: 3}}
      result = %Result{directives: [directive]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Should only have the new instruction after removing current one
      assert :queue.len(updated_agent.pending_instructions) == 2
      {{:value, first}, _q1} = :queue.out(updated_agent.pending_instructions)
      assert first.action == EnqueueAction
      assert first.params.value == 2
    end

    test "handles partial directive application failure", %{agent: agent} do
      directives = [
        %EnqueueDirective{action: Add, params: %{value: 1}},
        # This will fail
        %EnqueueDirective{action: nil},
        %EnqueueDirective{action: Add, params: %{value: 2}}
      ]

      result = %Result{directives: directives}

      {:error, :invalid_action} = Directive.apply_agent_directives(agent, result)

      # Queue should be empty since we rollback on failure
      assert :queue.is_empty(agent.pending_instructions)
    end

    test "handles recursive directive application", %{agent: agent} do
      # Create a directive that will trigger another directive
      nested_directive = %EnqueueDirective{
        action: EnqueueAction,
        params: %{
          action: EnqueueAction,
          params: %{
            action: Add,
            params: %{value: 1}
          }
        }
      }

      result = %Result{directives: [nested_directive]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify the nested structure is maintained
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == EnqueueAction
      assert instruction.params.action == EnqueueAction
      assert instruction.params.params.action == Add
    end

    test "handles max queue size limits", %{agent: agent} do
      # Create more directives than a reasonable queue should handle
      large_directive_list =
        Enum.map(1..1000, fn i ->
          %EnqueueDirective{action: Add, params: %{value: i}}
        end)

      result = %Result{directives: large_directive_list}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify queue integrity with large number of instructions
      assert :queue.len(updated_agent.pending_instructions) == 1000
      {{:value, first}, _} = :queue.out(updated_agent.pending_instructions)
      assert first.action == Add
      assert first.params.value == 1
    end

    test "handles invalid queue states", %{agent: agent} do
      # Simulate corrupted queue state
      corrupted_agent = %{agent | pending_instructions: :not_a_queue}

      directive = %EnqueueDirective{action: Add, params: %{value: 1}}
      result = %Result{directives: [directive]}

      assert_raise ArgumentError, fn ->
        Directive.apply_agent_directives(corrupted_agent, result)
      end
    end

    test "handles mixed directive types with queue operations", %{agent: agent} do
      # Mix different types of directives that affect the queue differently
      directives = [
        # Use proper test action module
        %RegisterActionDirective{action_module: JidoTest.TestActions.Add},
        %EnqueueDirective{action: JidoTest.TestActions.Add, params: %{value: 1}},
        %DeregisterActionDirective{action_module: JidoTest.TestActions.Add}
      ]

      result = %Result{directives: directives}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify final state
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert instruction.action == JidoTest.TestActions.Add
      assert instruction.params.value == 1
      # Should be deregistered
      refute JidoTest.TestActions.Add in updated_agent.actions
    end

    test "handles empty directive list with existing queue", %{agent: agent} do
      # Setup initial queue state
      initial_instruction = %Instruction{action: Add, params: %{value: 1}}

      agent = %{
        agent
        | pending_instructions: :queue.in(initial_instruction, agent.pending_instructions)
      }

      # Apply empty directive list
      result = %Result{directives: []}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Should have removed current instruction but added nothing new
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "handles directive application with dirty state", %{agent: agent} do
      # Set dirty state flag
      agent = %{agent | dirty_state?: true}

      directive = %EnqueueDirective{action: Add, params: %{value: 1}}
      result = %Result{directives: [directive]}

      {:ok, updated_agent} = Directive.apply_agent_directives(agent, result)

      # Verify dirty state is preserved
      assert updated_agent.dirty_state?
      assert :queue.len(updated_agent.pending_instructions) == 1
    end
  end
end
