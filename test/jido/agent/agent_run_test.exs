defmodule JidoTest.AgentRunTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestAgents.{
    BasicAgent,
    FullFeaturedAgent,
    ErrorHandlingAgent,
    CallbackTrackingAgent
  }

  alias JidoTest.TestActions

  @moduletag :capture_log

  describe "run/2" do
    setup do
      {:ok, agent: FullFeaturedAgent.new()}
    end

    test "executes single action", %{agent: agent} do
      {:ok, planned} =
        FullFeaturedAgent.plan(agent, {TestActions.Add, %{value: 10, amount: 1}})

      {:ok, final, _directives} = FullFeaturedAgent.run(planned)

      assert final.result.value == 11
      assert final.state.status == :idle
      assert final.state.last_result_at != nil
    end

    test "updates agent state when apply_state: true", %{agent: agent} do
      {:ok, planned} =
        FullFeaturedAgent.plan(agent, {TestActions.Add, %{value: 10, amount: 1}})

      {:ok, final, _directives} = FullFeaturedAgent.run(planned, apply_state: true)

      assert final.result.value == 11
    end

    test "preserves original state when apply_state: false", %{agent: agent} do
      {:ok, planned} =
        FullFeaturedAgent.plan(agent, {TestActions.Add, %{value: 10, amount: 5}})

      {:ok, final, _directives} = FullFeaturedAgent.run(planned, apply_state: false)

      # Original state preserved
      assert final.state.value == 0
      # Result contains new state
      assert final.result.value == 15
    end

    test "executes list of action tuples", %{agent: agent} do
      {:ok, planned} =
        FullFeaturedAgent.plan(
          agent,
          [
            {TestActions.Add, %{value: 10, amount: 1}},
            {TestActions.Multiply, %{amount: 2}},
            {TestActions.Add, %{amount: 8}}
          ]
        )

      {:ok, final, _directives} = FullFeaturedAgent.run(planned, runner: Jido.Runner.Chain)

      # (10 + 1) * 2 + 8
      assert final.result.value == 30
    end

    test "handles errors appropriately" do
      agent = ErrorHandlingAgent.new()
      {:ok, agent} = ErrorHandlingAgent.set(agent, %{should_recover?: false})
      {:ok, planned} = ErrorHandlingAgent.plan(agent, {TestActions.ErrorAction, %{}})
      {:error, error} = ErrorHandlingAgent.run(planned)

      assert error.type == :execution_error
      assert error.message == "Workflow failed"
    end

    test "tracks callbacks in correct order" do
      agent = CallbackTrackingAgent.new()
      {:ok, planned} = CallbackTrackingAgent.plan(agent, {TestActions.Add, %{value: 1}})
      {:ok, final, _directives} = CallbackTrackingAgent.run(planned)

      callbacks = Enum.map(final.state.callback_log, & &1.callback)
      assert :on_before_run in callbacks
      assert :on_after_run in callbacks
    end

    test "preserves state on action error with apply_state: true" do
      agent = ErrorHandlingAgent.new()

      {:ok, agent} = ErrorHandlingAgent.set(agent, %{battery_level: 100, should_recover?: false})

      {:ok, planned} = ErrorHandlingAgent.plan(agent, {TestActions.ErrorAction, %{}})
      {:error, error} = ErrorHandlingAgent.run(planned, apply_state: true)

      # Error result should be stored
      assert error.type == :execution_error
      assert error.message == "Workflow failed"
    end

    test "attempts recovery on error" do
      agent = ErrorHandlingAgent.new()
      {:ok, agent} = ErrorHandlingAgent.set(agent, %{battery_level: 100, should_recover?: true})

      {:ok, planned} = ErrorHandlingAgent.plan(agent, {TestActions.ErrorAction, %{}})
      {:ok, recovered_agent, []} = ErrorHandlingAgent.run(planned, apply_state: true)

      # Recovery should have incremented error count
      assert recovered_agent.state.error_count == 1
      # Last error should be stored
      assert recovered_agent.state.last_error.type == :execution_error
      assert recovered_agent.state.last_error.message =~ "Workflow failed"
    end

    test "prevents calling run with wrong agent module" do
      agent = BasicAgent.new()
      assert {:error, error} = FullFeaturedAgent.run(agent, apply_state: true)
      assert error.type == :validation_error

      assert error.message =~
               "Invalid agent type. Expected #{BasicAgent}, got #{FullFeaturedAgent}"
    end

    test "validates runner module existence" do
      agent = BasicAgent.new()
      {:ok, planned} = BasicAgent.plan(agent, TestActions.BasicAction)
      {:error, error} = BasicAgent.run(planned, runner: NonExistentRunner)

      assert error.type == :validation_error

      assert error.message =~
               "Runner module #{inspect(NonExistentRunner)} must exist and implement run/2"
    end

    test "handles empty instruction queue gracefully", %{agent: _agent} do
      agent = BasicAgent.new()
      {:ok, final, _directives} = BasicAgent.run(agent)
      assert final.state == agent.state
    end

    test "processes large instruction queues without stack overflow", %{agent: agent} do
      qty = 1000
      actions = List.duplicate({TestActions.Add, %{value: 0, amount: 1}}, qty)
      {:ok, planned} = FullFeaturedAgent.plan(agent, actions)
      {:ok, final, _directives} = FullFeaturedAgent.run(planned, runner: Jido.Runner.Chain)

      assert final.result.value == qty
    end
  end

  describe "apply_agent_directives/3" do
    test "applies directives from result" do
      agent = BasicAgent.new()

      # Plan an enqueue action that will enqueue an Add action
      {:ok, planned} =
        BasicAgent.plan(agent, {
          TestActions.EnqueueAction,
          %{
            action: TestActions.Add,
            params: %{value: 1, amount: 5}
          }
        })

      # Run the enqueue action
      {:ok, final, []} = BasicAgent.run(planned, runner: Jido.Runner.Simple)

      # Verify the directive was applied by checking the pending instructions
      assert :queue.len(final.pending_instructions) > 0
    end

    test "applies register directive from result" do
      agent = BasicAgent.new()

      # Plan a register action
      {:ok, planned} =
        BasicAgent.plan(agent, {
          TestActions.RegisterAction,
          %{
            action_module: TestActions.BasicAction
          }
        })

      # Run the register action
      {:ok, final, _directives} = BasicAgent.run(planned)

      # Verify the action module was registered
      assert final.actions |> Enum.member?(TestActions.BasicAction)
    end

    test "applies deregister directive from result" do
      agent = BasicAgent.new()

      # First, register an action
      {:ok, planned_register} =
        BasicAgent.plan(agent, {
          TestActions.RegisterAction,
          %{
            action_module: TestActions.BasicAction
          }
        })

      {:ok, agent_with_registered_action, _directives} = BasicAgent.run(planned_register)

      # Plan a deregister action
      {:ok, planned_deregister} =
        BasicAgent.plan(agent_with_registered_action, {
          TestActions.DeregisterAction,
          %{
            action_module: TestActions.BasicAction
          }
        })

      # Run the deregister action
      {:ok, final, _directives} = BasicAgent.run(planned_deregister)
      # Verify the action module was deregistered
      refute final.actions |> Enum.member?(TestActions.BasicAction)
    end
  end
end
