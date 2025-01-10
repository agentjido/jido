defmodule JidoTest.AgentCmdTest do
  use ExUnit.Case, async: true

  alias JidoTest.TestAgents.{
    FullFeaturedAgent,
    CallbackTrackingAgent
  }

  alias JidoTest.TestActions
  alias Jido.Runner.Chain

  @moduletag :capture_log

  describe "cmd/4" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "executes single action with params", %{agent: agent} do
      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add,
           %{
             value: 10,
             amount: 5
           }},
          %{},
          runner: Chain
        )

      assert final.state.value == 15
      assert :queue.is_empty(final.pending_instructions)
      assert final.dirty_state? == false
      assert final.state.status == :busy
      assert final.state.last_result_at != nil
    end

    test "executes list of action tuples", %{agent: agent} do
      instructions = [
        {TestActions.Add, %{value: 10, amount: 1}},
        {TestActions.Multiply, %{amount: 2}},
        {TestActions.Add, %{amount: 8}}
      ]

      {:ok, final} = FullFeaturedAgent.cmd(agent, instructions, %{}, runner: Chain)

      assert final.state.value == 30
      assert :queue.is_empty(final.pending_instructions)
      assert final.dirty_state? == false
      assert final.state.status == :busy
      assert final.state.last_result_at != nil
    end

    test "preserves state with apply_state: false", %{agent: agent} do
      # Initial state
      assert agent.state.location == :home
      assert agent.state.value == 0

      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 42}},
          %{},
          apply_state: false,
          runner: Chain
        )

      # Original state preserved
      assert final.state.location == :home
      assert final.state.value == 0
      assert :queue.is_empty(final.pending_instructions)
      assert final.dirty_state? == false
      # Result contains new state
      assert final.result.result_state.value == 43
    end

    test "enforces schema validation with strict_validation: true", %{agent: agent} do
      # Try to set an unknown field with strict validation
      assert {:error, error} =
               FullFeaturedAgent.cmd(
                 agent,
                 {TestActions.Add, %{value: 10}},
                 %{unknown_field: "test"},
                 strict_validation: true,
                 runner: Chain
               )

      assert error.type == :validation_error
      assert error.message =~ "Strict validation is enabled"
      assert error.message =~ "unknown_field"

      # Verify same command works without strict validation
      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 10}},
          %{unknown_field: "test"},
          strict_validation: false,
          runner: Chain
        )

      assert final.state.value == 11
      assert final.state.unknown_field == "test"
    end

    test "handles unregistered actions", %{agent: agent} do
      assert {:error, error} =
               FullFeaturedAgent.cmd(agent, UnregisteredAction, %{}, runner: Chain)

      assert error.type == :config_error
      assert error.message =~ "Action not registered"
    end

    test "tracks callbacks in correct order" do
      agent = CallbackTrackingAgent.new()

      {:ok, final} =
        CallbackTrackingAgent.cmd(
          agent,
          {TestActions.Add,
           %{
             value: 10,
             amount: 5
           }},
          %{},
          runner: Chain
        )

      callbacks = Enum.map(final.state.callback_log, & &1.callback)

      assert :on_before_run in callbacks
      # assert :on_after_run in callbacks
      # assert :on_after_directives in callbacks
      # IO.inspect(callbacks)
      assert final.state.value == 15
    end
  end

  describe "cmd/4 edge cases" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "handles empty instruction list", %{agent: agent} do
      {:ok, final} = FullFeaturedAgent.cmd(agent, [], %{}, runner: Chain)

      assert :queue.is_empty(final.pending_instructions)
      assert final.dirty_state? == false
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
          runner: Chain
        )

      assert error.type == :validation_error
      assert error.message =~ "Invalid state update. Expected a map or keyword list, got nil"
    end

    test "handles empty attributes", %{agent: agent} do
      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 1}},
          %{},
          runner: Chain
        )

      assert final.state.value == 2
    end

    test "handles nil context in opts", %{agent: agent} do
      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          {TestActions.Add, %{value: 1}},
          %{},
          context: nil,
          runner: Chain
        )

      assert final.state.value == 2
    end

    test "invalid agent struct type returns error" do
      invalid_agent = %{__struct__: InvalidAgent}

      assert {:error, error} =
               FullFeaturedAgent.cmd(
                 invalid_agent,
                 {TestActions.Add, %{value: 1}},
                 %{},
                 runner: Chain
               )

      assert error.type == :validation_error
      assert error.message =~ "Invalid agent type"
    end

    test "handles multiple errors in action chain", %{agent: agent} do
      instructions = [
        {TestActions.Add, %{value: "invalid"}},
        {TestActions.Multiply, %{amount: "also_invalid"}},
        {TestActions.Add, %{amount: 5}}
      ]

      assert {:error, result} =
               FullFeaturedAgent.cmd(
                 agent,
                 instructions,
                 %{},
                 runner: Chain
               )

      assert result.error.type == :validation_error
      # Chain should stop at first error
      # Original value unchanged
      assert result.result_state.value == 0
    end

    test "handles extremely large instruction lists", %{agent: agent} do
      large_instruction_list =
        Enum.map(1..1000, fn i ->
          {TestActions.Add, %{amount: i}}
        end)

      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          large_instruction_list,
          %{},
          runner: Chain
        )

      # Sum of numbers 1 to 1000
      assert final.state.value == 500_500
    end

    test "maintains state consistency on error", %{agent: agent} do
      original_state = agent.state

      assert {:error, _} =
               FullFeaturedAgent.cmd(
                 agent,
                 {UnregisteredAction, %{value: 42}},
                 %{status: :running},
                 runner: Chain
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

      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          recursive_instructions,
          %{},
          runner: Chain
        )

      assert final.state.value == 3
    end

    test "handles all types of valid instructions", %{agent: agent} do
      mixed_instructions = [
        # Module only
        TestActions.Add,
        # Tuple with params
        {TestActions.Add, %{value: 1}},
        # Empty params
        {TestActions.Add, %{}},
        # Nil params
        {TestActions.Add, nil}
      ]

      {:ok, final} =
        FullFeaturedAgent.cmd(
          agent,
          mixed_instructions,
          %{},
          runner: Chain
        )

      assert :queue.is_empty(final.pending_instructions)
      assert final.dirty_state? == false
    end
  end
end
