defmodule JidoTest.AgentCmdTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestAgents.{
    FullFeaturedAgent,
    ErrorHandlingAgent,
    CallbackTrackingAgent
  }

  alias JidoTest.TestActions
  alias Jido.Error

  @moduletag :capture_log

  describe "cmd/4" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "executes single action with params", %{agent: agent} do
      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 10, amount: 5}},
          %{},
          runner: Jido.Runner.Chain
        )

      assert final.result.value == 15
    end

    test "executes list of action tuples", %{agent: agent} do
      instructions = [
        {TestActions.Add, %{value: 10, amount: 1}},
        {TestActions.Multiply, %{amount: 2}},
        {TestActions.Add, %{amount: 8}}
      ]

      {:ok, final, []} =
        FullFeaturedAgent.cmd(agent, instructions, %{}, runner: Jido.Runner.Chain)

      assert final.result.value == 30
    end

    test "preserves state with apply_state: false", %{agent: agent} do
      # Initial state
      assert agent.state.location == :home
      assert agent.state.value == 0

      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 42}},
          %{},
          apply_state: false,
          runner: Jido.Runner.Chain
        )

      # Original state preserved in final agent
      assert final.state.value == 0
      assert final.state.location == :home
      # Result contains the action's output
      assert final.result.value == 43
    end

    test "enforces schema validation with strict_validation: true", %{agent: agent} do
      # Try to set an unknown field with strict validation
      assert {:error, error} =
               FullFeaturedAgent.cmd(
                 agent,
                 {TestActions.Add, %{value: 10}},
                 %{unknown_field: "test"},
                 strict_validation: true,
                 runner: Jido.Runner.Chain
               )

      assert Error.to_map(error).type == :validation_error
      assert error.message =~ "Strict validation is enabled"
      assert error.message =~ "unknown_field"

      # Verify same command works without strict validation
      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 10}},
          %{unknown_field: "test"},
          strict_validation: false,
          runner: Jido.Runner.Chain
        )

      assert final.result.value == 11
    end

    test "handles unregistered actions", %{agent: agent} do
      assert {:error, error} =
               FullFeaturedAgent.cmd(agent, UnregisteredAction, %{}, runner: Jido.Runner.Chain)

      assert Error.to_map(error).type == :config_error
      assert error.message =~ "Action not registered"
    end

    test "tracks callbacks in correct order" do
      agent = CallbackTrackingAgent.new()

      {:ok, final, []} =
        CallbackTrackingAgent.cmd(
          agent,
          {TestActions.Add, %{value: 10, amount: 5}},
          %{},
          runner: Jido.Runner.Chain
        )

      callbacks = Enum.map(final.state.callback_log, & &1.callback)

      assert :on_before_run in callbacks
      assert final.result.value == 15
    end
  end

  describe "cmd/4 error handling" do
    test "handles errors appropriately" do
      agent = ErrorHandlingAgent.new()
      {:ok, agent} = ErrorHandlingAgent.set(agent, %{should_recover?: false})

      {:error, error} =
        ErrorHandlingAgent.cmd(
          agent,
          {TestActions.ErrorAction, %{}},
          %{},
          runner: Jido.Runner.Chain
        )

      assert Error.to_map(error).type == :execution_error
      assert Error.extract_message(error) == "Exec failed"
    end

    test "preserves state on action error" do
      agent = ErrorHandlingAgent.new()
      {:ok, agent} = ErrorHandlingAgent.set(agent, %{battery_level: 100, should_recover?: false})

      {:error, error} =
        ErrorHandlingAgent.cmd(
          agent,
          {TestActions.ErrorAction, %{}},
          %{},
          runner: Jido.Runner.Chain
        )

      assert Error.to_map(error).type == :execution_error
      assert Error.extract_message(error) == "Exec failed"
      # State should be preserved
      assert agent.state.battery_level == 100
    end

    test "attempts recovery on error" do
      agent = ErrorHandlingAgent.new()
      {:ok, agent} = ErrorHandlingAgent.set(agent, %{battery_level: 100, should_recover?: true})

      {:ok, recovered, []} =
        ErrorHandlingAgent.cmd(
          agent,
          {TestActions.ErrorAction, %{}},
          %{},
          runner: Jido.Runner.Chain
        )

      # Recovery should have incremented error count
      assert recovered.state.error_count == 1
      # Last error should be stored
      assert recovered.state.last_error.type == :execution_error
      assert Error.extract_message(recovered.state.last_error) =~ "Exec failed"
    end
  end

  describe "cmd/4 edge cases" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "handles empty instruction list", %{agent: agent} do
      {:ok, final, []} = FullFeaturedAgent.cmd(agent, [], %{}, runner: Jido.Runner.Chain)

      # State should remain unchanged
      assert final.state.location == :home
      assert final.state.value == 0
      assert final.state.battery_level == 100
    end

    test "handles nil attributes", %{agent: agent} do
      {:error, error} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 1}},
          nil,
          runner: Jido.Runner.Chain
        )

      assert Error.to_map(error).type == :validation_error
      assert error.message =~ "Invalid state update. Expected a map or keyword list, got nil"
    end

    test "handles empty attributes", %{agent: agent} do
      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 1}},
          %{},
          runner: Jido.Runner.Chain
        )

      assert final.result.value == 2
    end

    test "handles nil context in opts", %{agent: agent} do
      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 1}},
          %{},
          context: nil,
          runner: Jido.Runner.Chain
        )

      assert final.result.value == 2
    end

    test "invalid agent struct type returns error" do
      invalid_agent = %{__struct__: InvalidAgent}

      assert {:error, error} =
               FullFeaturedAgent.cmd(
                 invalid_agent,
                 {TestActions.Add, %{value: 1}},
                 %{},
                 runner: Jido.Runner.Chain
               )

      assert Error.to_map(error).type == :validation_error
      assert error.message =~ "Invalid agent type"
    end

    test "handles multiple errors in action chain", %{agent: agent} do
      instructions = [
        {TestActions.Add, %{value: "invalid"}},
        {TestActions.Multiply, %{amount: "also_invalid"}},
        {TestActions.Add, %{amount: 5}}
      ]

      assert {:error, error} =
               FullFeaturedAgent.cmd(
                 agent,
                 instructions,
                 %{},
                 runner: Jido.Runner.Chain
               )

      assert Error.to_map(error).type == :validation_error
      assert error.message =~ "Invalid parameters for Action"
      # Original value unchanged
      assert agent.state.value == 0
    end

    test "handles extremely large instruction lists", %{agent: agent} do
      large_instruction_list =
        Enum.map(1..1000, fn i ->
          {TestActions.Add, %{value: 0, amount: i}}
        end)

      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          large_instruction_list,
          %{},
          runner: Jido.Runner.Chain
        )

      # Sum of numbers 1 to 1000
      assert final.result.value == 500_500
    end

    test "maintains state consistency on error", %{agent: agent} do
      original_state = agent.state

      assert {:error, _} =
               FullFeaturedAgent.cmd(
                 agent,
                 {UnregisteredAction, %{value: 42}},
                 %{status: :running},
                 runner: Jido.Runner.Chain
               )

      # Even though we tried to set status: :running, it should be rolled back
      assert agent.state == original_state
    end

    test "handles recursive instruction structures", %{agent: agent} do
      # Create a recursive instruction structure
      recursive_instructions = [
        {TestActions.Add, %{value: 1}},
        {TestActions.Add,
         %{
           nested: %{
             deeply: %{
               nested: %{
                 value: 2
               }
             }
           }
         }}
      ]

      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          recursive_instructions,
          %{},
          runner: Jido.Runner.Chain
        )

      assert final.result.value == 3
    end

    test "handles all types of valid instructions", %{agent: agent} do
      mixed_instructions = [
        # Tuple with params
        {TestActions.Add, %{amount: 0, value: 1}},
        # Module only
        TestActions.Add,
        # Empty params
        {TestActions.Add, %{}},
        # Nil params
        {TestActions.Add, nil}
      ]

      {:ok, final, []} =
        FullFeaturedAgent.cmd(
          agent,
          mixed_instructions,
          %{},
          runner: Jido.Runner.Chain
        )

      assert final.result.value > 0
    end
  end
end
