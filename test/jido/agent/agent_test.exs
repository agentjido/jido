defmodule JidoTest.AgentTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Basic.Log
  alias Jido.Actions.Basic.Sleep
  alias JidoTest.SimpleAgent

  describe "SimpleAgent.new/1" do
    test "creates an agent with default values" do
      agent = SimpleAgent.new()
      assert agent.id != nil
      assert agent.location == :home
      assert agent.battery_level == 100
    end

    test "creates an agent with custom id" do
      custom_id = "custom_id"
      agent = SimpleAgent.new(custom_id)
      assert agent.id == custom_id
    end

    test "generates unique ids for multiple agents" do
      agent1 = SimpleAgent.new()
      agent2 = SimpleAgent.new()
      assert agent1.id != agent2.id
    end
  end

  describe "Agent metadata" do
    test "to_json/0 returns agent metadata" do
      json = SimpleAgent.to_json()
      assert json.name == "SimpleBot"
      assert is_list(json.schema)
    end

    test "name/0 returns the agent name" do
      assert SimpleAgent.name() == "SimpleBot"
    end

    test "description/0 returns the agent description" do
      assert SimpleAgent.description() == nil
    end

    test "category/0 returns the agent category" do
      assert SimpleAgent.category() == nil
    end

    test "tags/0 returns the agent tags" do
      assert SimpleAgent.tags() == []
    end

    test "vsn/0 returns the agent version" do
      assert SimpleAgent.vsn() == nil
    end

    test "schema/0 returns the agent schema" do
      schema = SimpleAgent.schema()
      assert Keyword.has_key?(schema, :location)
      assert Keyword.has_key?(schema, :battery_level)
    end

    test "default planner and runner are set on BasicAgent" do
      assert JidoTest.BasicAgent.planner() == Jido.Planner.Direct
      assert JidoTest.BasicAgent.runner() == Jido.Runner.Chain
    end

    test "specified planner and runner are set on SimpleAgent" do
      assert SimpleAgent.planner() == JidoTest.SimpleAgent.Planner
      assert SimpleAgent.runner() == JidoTest.SimpleAgent.Runner
    end
  end

  describe "SimpleAgent.set/2" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "updates agent attributes", %{agent: agent} do
      assert agent.dirty_state? == false

      {:ok, updated_agent} = SimpleAgent.set(agent, %{location: :office, battery_level: 80})
      assert updated_agent.location == :office
      assert updated_agent.battery_level == 80
      assert updated_agent.dirty_state? == true
    end

    test "returns error for invalid attributes", %{agent: agent} do
      {:error, error_message} =
        SimpleAgent.set(agent, %{location: "invalid", battery_level: "full"})

      assert error_message =~ "Invalid parameters for Agent"
    end

    test "handles partial updates", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.set(agent, %{location: :park})
      assert updated_agent.location == :park
      assert updated_agent.battery_level == 100
    end

    test "handles empty update", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.set(agent, %{})
      assert updated_agent == agent
      assert updated_agent.dirty_state? == false
      assert agent.dirty_state? == false
    end
  end

  describe "SimpleAgent.validate/1" do
    test "returns :ok for valid agent state" do
      agent = SimpleAgent.new()
      assert {:ok, ^agent} = SimpleAgent.validate(agent)
    end

    test "returns error for invalid agent state" do
      agent = SimpleAgent.new()
      invalid_agent = %{agent | battery_level: "not a number"}
      assert {:error, error_message} = SimpleAgent.validate(invalid_agent)
      assert error_message =~ "Invalid parameters for Agent"
    end

    test "validates custom attributes" do
      agent = SimpleAgent.new()
      invalid_agent = Map.put(agent, :custom_field, "invalid")
      assert {:error, error_message} = SimpleAgent.validate(invalid_agent)
      assert error_message =~ "Invalid parameters for Agent"
    end
  end

  describe "SimpleAgent.plan/3" do
    test "returns a list of actions with default command and params" do
      agent = SimpleAgent.new()
      assert {:ok, planned_agent} = SimpleAgent.plan(agent)
      assert :queue.len(planned_agent.pending) == 3
      assert planned_agent.dirty_state? == true

      actions = :queue.to_list(planned_agent.pending)

      assert actions == [
               {Log, message: "Hello, world!"},
               {Sleep, duration: 50},
               {Log, message: "Goodbye, world!"}
             ]
    end

    test "handles different commands with correct plans" do
      agent = SimpleAgent.new()

      # Test :custom command
      {:ok, custom_agent} = SimpleAgent.plan(agent, :custom, %{message: "Test message"})
      custom_actions = :queue.to_list(custom_agent.pending)

      assert custom_actions == [
               {Log, message: "Test message"},
               {Sleep, duration: 100},
               {Log, message: "Custom command completed"}
             ]

      # Test :sleep command
      {:ok, sleep_agent} = SimpleAgent.plan(agent, :sleep, %{duration: 200})
      sleep_actions = :queue.to_list(sleep_agent.pending)

      assert sleep_actions == [
               {Log, message: "Going to sleep..."},
               {Sleep, duration: 200},
               {Log, message: "Waking up!"}
             ]

      # Test unknown command
      {:ok, unknown_agent} = SimpleAgent.plan(agent, :invalid, %{})
      unknown_actions = :queue.to_list(unknown_agent.pending)

      assert unknown_actions == [
               {Log, message: "Unknown command: :invalid"},
               {Log, message: "Please use :default, :move, :recharge, or :sleep"}
             ]
    end

    test "preserves agent state while adding actions" do
      agent = SimpleAgent.new()
      {:ok, agent_with_state} = SimpleAgent.set(agent, %{location: :office})
      {:ok, planned_agent} = SimpleAgent.plan(agent_with_state)

      assert planned_agent.location == :office
      assert :queue.len(planned_agent.pending) == 3
      assert planned_agent.dirty_state? == true
    end

    test "appends new actions to existing pending queue" do
      agent = SimpleAgent.new()

      # Chain multiple different commands
      {:ok, agent1} = SimpleAgent.plan(agent, :default)
      {:ok, agent2} = SimpleAgent.plan(agent1, :custom, %{message: "Custom"})
      {:ok, agent3} = SimpleAgent.plan(agent2, :sleep, %{duration: 100})

      actions = :queue.to_list(agent3.pending)
      assert length(actions) == 9

      # Verify the sequence of all actions
      assert actions == [
               {Log, message: "Hello, world!"},
               {Sleep, duration: 50},
               {Log, message: "Goodbye, world!"},
               {Log, message: "Custom"},
               {Sleep, duration: 100},
               {Log, message: "Custom command completed"},
               {Log, message: "Going to sleep..."},
               {Sleep, duration: 100},
               {Log, message: "Waking up!"}
             ]
    end
  end

  describe "SimpleAgent.run/1" do
    setup do
      agent = SimpleAgent.new()

      plan = [
        {Log, message: "Hello, world!"},
        {Sleep, duration: 50},
        {Log, message: "Goodbye, world!"}
      ]

      {:ok, agent: agent, plan: plan}
    end

    test "executes pending actions and returns updated agent", %{agent: agent} do
      {:ok, agent_with_plan} = SimpleAgent.plan(agent)
      {:ok, final_agent} = SimpleAgent.run(agent_with_plan)

      assert final_agent.pending == :queue.new()
      assert final_agent.dirty_state? == false
    end

    test "returns error if runner fails", %{agent: agent} do
      # Create invalid action to force runner error
      invalid_agent = %{agent | pending: :queue.from_list([{InvalidAction, []}])}
      assert {:error, _reason} = SimpleAgent.run(invalid_agent)
    end

    test "applies state changes when apply_state is true", %{agent: agent} do
      {:ok, agent_with_plan} = SimpleAgent.plan(agent)
      {:ok, final_agent} = SimpleAgent.run(agent_with_plan, apply_state: true)

      assert final_agent.pending == :queue.new()
      assert final_agent.dirty_state? == false
    end

    test "preserves original state when apply_state is false", %{agent: agent} do
      {:ok, agent_with_plan} = SimpleAgent.plan(agent)
      {:ok, final_agent, _result} = SimpleAgent.run(agent_with_plan, apply_state: false)

      assert final_agent.pending == :queue.new()
      assert final_agent.dirty_state? == false

      assert Map.drop(final_agent, [:pending, :dirty_state?]) ==
               Map.drop(agent_with_plan, [:pending, :dirty_state?])
    end
  end

  describe "SimpleAgent.act/2" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "validates, updates state, plans and executes actions", %{agent: agent} do
      assert agent.location == :home

      {:ok, updated_agent} =
        SimpleAgent.act(agent, :custom, %{
          location: :office,
          message: "Hello from the office!"
        })

      assert updated_agent.location == :office
      assert updated_agent.pending == :queue.new()
      assert updated_agent.dirty_state? == false
    end

    test "returns error when validation fails", %{agent: agent} do
      invalid_attrs = %{battery_level: "not a number"}
      assert {:error, reason} = SimpleAgent.act(agent, :default, invalid_attrs)
      assert is_binary(reason)
      assert String.contains?(reason, "Invalid parameters for Agent")
    end

    test "handles empty params with default command", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.act(agent)

      # Default command should still execute successfully
      assert updated_agent.pending == :queue.new()
      assert updated_agent.dirty_state? == false
      # The agent's state should remain unchanged since we didn't provide any new state
      assert updated_agent.location == agent.location
      assert updated_agent.battery_level == agent.battery_level
    end

    test "preserves state when apply_state is false", %{agent: agent} do
      params = %{location: :park, battery_level: 75}
      {:ok, updated_agent, _result} = SimpleAgent.act(agent, :default, params, apply_state: false)

      # Original state should be preserved
      assert updated_agent.location == :home
      assert updated_agent.battery_level == 100
      assert updated_agent.pending == :queue.new()
      assert updated_agent.dirty_state? == false
    end

    test "handles unknown commands", %{agent: agent} do
      {:ok, updated_agent} = SimpleAgent.act(agent, :unknown_command)

      # Should still execute but with fallback plan
      assert updated_agent.pending == :queue.new()
      assert updated_agent.dirty_state? == false
    end
  end

  describe "SimpleAgent.reset/1" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "clears pending actions queue", %{agent: agent} do
      # First add some actions to the queue
      {:ok, planned_agent} = SimpleAgent.plan(agent)
      assert SimpleAgent.pending?(planned_agent) > 0

      # Reset should clear the queue
      {:ok, reset_agent} = SimpleAgent.reset(planned_agent)
      assert SimpleAgent.pending?(reset_agent) == 0
    end

    test "maintains other agent state", %{agent: agent} do
      # Modify agent state
      {:ok, modified_agent} = SimpleAgent.set(agent, %{location: :office, battery_level: 75})
      {:ok, planned_agent} = SimpleAgent.plan(modified_agent)

      # Reset should only clear queue
      {:ok, reset_agent} = SimpleAgent.reset(planned_agent)
      assert reset_agent.location == :office
      assert reset_agent.battery_level == 75
    end
  end

  describe "SimpleAgent.pending?/1" do
    setup do
      {:ok, agent: SimpleAgent.new()}
    end

    test "returns 0 for new agent", %{agent: agent} do
      assert SimpleAgent.pending?(agent) == 0
    end

    test "returns correct count after planning", %{agent: agent} do
      {:ok, planned_agent} = SimpleAgent.plan(agent)
      # Based on default plan
      assert SimpleAgent.pending?(planned_agent) == 3
    end

    test "returns correct count after custom plan", %{agent: agent} do
      {:ok, planned_agent} = SimpleAgent.plan(agent, :custom, %{message: "test"})
      # Based on custom plan
      assert SimpleAgent.pending?(planned_agent) == 3
    end

    test "returns 0 after running actions", %{agent: agent} do
      {:ok, planned_agent} = SimpleAgent.plan(agent)
      {:ok, run_agent} = SimpleAgent.run(planned_agent)
      assert SimpleAgent.pending?(run_agent) == 0
    end
  end
end
