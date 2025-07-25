defmodule JidoTest.AgentStateTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestAgents.{
    BasicAgent,
    FullFeaturedAgent
  }

  alias JidoTest.TestActions
  alias Jido.Error

  @moduletag :capture_log
  describe "state management" do
    setup do
      agent = BasicAgent.new()
      {:ok, agent: agent}
    end

    test "updates agent state with valid data", %{agent: agent} do
      {:ok, updated} =
        BasicAgent.set(agent, %{
          location: :office,
          battery_level: 80
        })

      assert updated.state.location == :office
      assert updated.state.battery_level == 80
      assert updated.dirty_state? == true
    end

    test "updates state with keyword list", %{agent: agent} do
      {:ok, updated} =
        BasicAgent.set(agent,
          location: :garage,
          battery_level: 90
        )

      assert updated.state.location == :garage
      assert updated.state.battery_level == 90
      assert updated.dirty_state? == true
    end

    test "validates state updates with invalid types", %{agent: agent} do
      assert {:error, error} =
               BasicAgent.set(agent, %{
                 # Should be atom
                 location: 123,
                 # Should be integer
                 battery_level: "full"
               })

      assert error.message =~ "Agent state validation failed"
      assert error.message =~ "invalid value for :location option: expected atom"

      # Original values should be unchanged
      assert agent.state.location == :home
      assert agent.state.battery_level == 100
      assert agent.dirty_state? == false
    end

    test "handles empty updates without changing state", %{agent: agent} do
      {:ok, updated} = BasicAgent.set(agent, %{})
      assert updated == agent
      assert updated.dirty_state? == false

      {:ok, updated2} = BasicAgent.set(agent, [])
      assert updated2 == agent
      assert updated2.dirty_state? == false
    end

    test "merges unknown fields into state with non-strict validation", %{agent: agent} do
      {:ok, updated} =
        BasicAgent.set(agent, %{
          unknown_field: true,
          another_unknown: "test",
          nested: %{
            field: 123
          }
        })

      assert updated.state.unknown_field == true
      assert updated.state.another_unknown == "test"
      assert updated.state.nested.field == 123
      assert updated.dirty_state? == true
    end

    test "rejects unknown fields with strict validation", %{agent: agent} do
      assert {:error, error} =
               BasicAgent.set(
                 agent,
                 %{
                   unknown_field: true,
                   another_unknown: "test"
                 },
                 strict_validation: true
               )

      assert error.message =~ "Agent state validation failed"
      assert error.message =~ "Unknown fields: [:unknown_field, :another_unknown]"
      assert agent.dirty_state? == false
    end

    test "deep merges state updates", %{agent: agent} do
      {:ok, step1} = BasicAgent.set(agent, %{nested: %{a: 1}})
      {:ok, step2} = BasicAgent.set(step1, %{nested: %{b: 2}})

      assert step2.state.nested.a == 1
      assert step2.state.nested.b == 2
      assert step2.dirty_state? == true
    end

    test "prevents calling set with wrong agent module" do
      agent = BasicAgent.new()
      assert {:error, error} = FullFeaturedAgent.set(agent, %{value: 42})
      assert Error.to_map(error).type == :validation_error

      assert error.message =~
               "Invalid agent type. Expected JidoTest.TestAgents.BasicAgent, got JidoTest.TestAgents.FullFeaturedAgent"
    end

    test "invalid state update with non-map or non-keyword list", %{agent: agent} do
      assert {:error, error} = BasicAgent.set(agent, true)
      assert error.message =~ "Invalid state update. Expected a map or keyword list, got true"

      assert {:error, error} = BasicAgent.set(agent, nil)
      assert error.message =~ "Invalid state update. Expected a map or keyword list, got nil"
    end
  end

  describe "validation callbacks" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "executes validation callbacks in order", %{agent: agent} do
      {:ok, updated} = FullFeaturedAgent.set(agent, %{status: :busy})

      assert updated.state.status == :busy
      assert updated.state.last_validated_at != nil
    end

    test "validation callbacks can modify state", %{agent: agent} do
      {:ok, updated} = FullFeaturedAgent.set(agent, %{metadata: %{test: true}})

      assert updated.state.metadata.test == true
      assert updated.state.last_validated_at != nil
    end

    test "prevents calling validate with wrong agent module" do
      agent = BasicAgent.new()
      assert {:error, error} = FullFeaturedAgent.validate(agent)
      assert Error.to_map(error).type == :validation_error

      assert error.message =~
               "Invalid agent type. Expected Elixir.JidoTest.TestAgents.BasicAgent, got Elixir.JidoTest.TestAgents.FullFeaturedAgent"
    end

    test "strict validation in callbacks", %{agent: agent} do
      assert {:error, error} =
               FullFeaturedAgent.validate(agent, strict_validation: true)

      assert error.message =~ "Agent state validation failed"
      assert error.message =~ "unknown fields were provided"
    end
  end

  describe "reset/1" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "resets agent state flags", %{agent: agent} do
      # Set up dirty state and result
      {:ok, dirty_agent} = FullFeaturedAgent.set(agent, %{value: 42})
      dirty_agent = %{dirty_agent | result: %{some: "result"}}
      assert dirty_agent.dirty_state? == true
      assert dirty_agent.result == %{some: "result"}

      # Reset agent
      {:ok, reset_agent} = FullFeaturedAgent.reset(dirty_agent)

      assert reset_agent.dirty_state? == false
      assert reset_agent.result == nil
      # State values should be preserved
      assert reset_agent.state.value == 42
    end
  end

  describe "pending?/1" do
    setup do
      agent = FullFeaturedAgent.new()
      {:ok, agent: agent}
    end

    test "returns 0 for empty instruction queue", %{agent: agent} do
      assert FullFeaturedAgent.pending?(agent) == 0
    end

    test "returns count of pending instructions", %{agent: agent} do
      {:ok, planned} =
        FullFeaturedAgent.plan(agent, [
          {TestActions.Add, %{value: 10}},
          {TestActions.Multiply, %{amount: 2}}
        ])

      assert FullFeaturedAgent.pending?(planned) == 2
    end
  end
end
