defmodule JidoTest.Examples.UserAgentTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestActions.{FormatUser, EnrichUserData, NotifyUser}

  @moduletag :capture_log

  defmodule UserAgent do
    use Jido.Agent,
      name: "user_agent",
      description: "Manages user registration",
      actions: [FormatUser, EnrichUserData, NotifyUser],
      schema: [
        # Input fields
        name: [type: {:or, [:string, nil]}, default: nil],
        email: [type: {:or, [:string, nil]}, default: nil],
        age: [type: {:or, [:integer, nil]}, default: nil],
        # Action results
        formatted_name: [type: {:or, [:string, nil]}, default: nil],
        username: [type: {:or, [:string, nil]}, default: nil],
        notification_sent: [type: :boolean, default: false]
      ]
  end

  @user_data %{
    # Note trailing space
    name: "John Doe ",
    # Will be normalized
    email: "JOHN@EXAMPLE.COM",
    age: 30
  }

  describe "new agent" do
    test "creates with empty state" do
      agent = UserAgent.new()

      # All fields start as defaults
      assert agent.state.name == nil
      assert agent.state.email == nil
      assert agent.state.age == nil
      assert agent.state.formatted_name == nil
      assert agent.state.username == nil
      assert agent.state.notification_sent == false
    end
  end

  describe "set operation" do
    setup do
      agent = UserAgent.new()
      {:ok, agent: agent}
    end

    test "sets single field", %{agent: agent} do
      {:ok, agent} = UserAgent.set(agent, name: "John Doe")
      assert agent.state.name == "John Doe"
    end

    test "sets multiple fields", %{agent: agent} do
      {:ok, agent} =
        UserAgent.set(agent, %{
          name: "John Doe",
          email: "john@example.com"
        })

      assert agent.state.name == "John Doe"
      assert agent.state.email == "john@example.com"
    end

    test "validates field values", %{agent: agent} do
      # Age must be integer
      result = UserAgent.set(agent, age: "thirty")
      assert {:error, _} = result
    end

    test "preserves unmodified fields", %{agent: agent} do
      {:ok, agent} = UserAgent.set(agent, name: "John")
      {:ok, agent} = UserAgent.set(agent, email: "john@example.com")

      assert agent.state.name == "John"
      assert agent.state.email == "john@example.com"
    end

    test "allows fields not specified in the schema", %{agent: agent} do
      {:ok, agent} = UserAgent.set(agent, status: :processing)
      assert agent.state.status == :processing
    end
  end

  describe "plan operation" do
    setup do
      agent = UserAgent.new()
      {:ok, agent} = UserAgent.set(agent, @user_data)
      {:ok, agent: agent}
    end

    test "plans single instruction", %{agent: agent} do
      {:ok, agent} = UserAgent.plan(agent, FormatUser)

      # Planning doesn't execute - state unchanged
      assert agent.state.name == "John Doe "
      assert agent.state.formatted_name == nil

      # But instruction is queued
      assert :queue.len(agent.pending_instructions) == 1
    end

    test "plans multiple instructions", %{agent: agent} do
      {:ok, agent} =
        UserAgent.plan(agent, [
          FormatUser,
          EnrichUserData
        ])

      # State remains unchanged
      assert agent.state.name == "John Doe "
      assert agent.state.formatted_name == nil
      assert agent.state.username == nil

      # Both instructions queued
      assert :queue.len(agent.pending_instructions) == 2
    end

    test "validates action registration", %{agent: agent} do
      # Try to plan unregistered action
      result = UserAgent.plan(agent, UnregisteredAction)
      assert {:error, _} = result
    end
  end

  describe "run operation" do
    setup do
      agent = UserAgent.new()
      {:ok, agent} = UserAgent.set(agent, @user_data)
      {:ok, agent: agent}
    end

    test "runs single action", %{agent: initial_agent} do
      # Plan then run
      # State is not used as parameters for the action, so it must be passed explicitly
      {:ok, planned_agent} =
        UserAgent.plan(initial_agent, {FormatUser, initial_agent.state})

      {:ok, result_agent, _directives} = UserAgent.run(planned_agent, apply_state: true)

      assert result_agent.result.formatted_name == "John Doe"
      assert result_agent.result.email == "john@example.com"

      # Result contains the initial state and the result state
      # assert result_agent.result.status == :ok
      # assert result_agent.result.email == result_agent.state.email
      # assert result_agent.result.formatted_name == result_agent.state.formatted_name
    end

    test "runs action chain", %{agent: initial_agent} do
      {:ok, planned_agent} =
        UserAgent.plan(initial_agent, [
          {FormatUser, initial_agent.state},
          EnrichUserData
        ])

      # Execute with state application to combine results
      {:ok, _result_agent, _directives} =
        UserAgent.run(planned_agent, apply_state: true)

      # From FormatUser
      # assert result_agent.result.formatted_name == "John Doe"

      # From EnrichUserData
      # assert result_agent.result.username == "john.doe"
    end

    test "run may not apply state changes to the agent", %{agent: initial_agent} do
      # First run FormatUser to get formatted data
      {:ok, planned_format_agent} =
        UserAgent.plan(initial_agent, {FormatUser, initial_agent.state})

      {:ok, format_result_agent, _directives} =
        UserAgent.run(planned_format_agent, apply_state: false)

      # Then run EnrichUserData with the formatted data
      {:ok, planned_enrich_agent} =
        UserAgent.plan(initial_agent, {EnrichUserData, format_result_agent.result})

      {:ok, result_agent, _directives} =
        UserAgent.run(planned_enrich_agent, apply_state: false)

      # State is not updated
      assert result_agent.state.formatted_name == initial_agent.state.formatted_name
      assert result_agent.state.email == initial_agent.state.email

      # Results from both actions are preserved
      assert format_result_agent.result.formatted_name == "John Doe"
      assert format_result_agent.result.email == "john@example.com"
      assert result_agent.result.username == "john.doe"
    end

    test "requires prior planning", %{agent: agent} do
      # Run without planning
      {:ok, agent, _directives} = UserAgent.run(agent)

      # State unchanged - nothing to run
      assert agent.state.formatted_name == nil
      assert agent.state.username == nil
    end

    test "clears instructions after run", %{agent: initial_agent} do
      {:ok, planned_agent} = UserAgent.plan(initial_agent, {FormatUser, initial_agent.state})
      {:ok, agent, _directives} = UserAgent.run(planned_agent)

      assert :queue.is_empty(agent.pending_instructions)
    end
  end

  describe "agent commands" do
    setup do
      agent = UserAgent.new()
      {:ok, agent} = UserAgent.set(agent, @user_data)
      {:ok, agent: agent}
    end

    test "can be used to set, plan and run instructions", %{agent: agent} do
      {:ok, agent, _directives} =
        UserAgent.cmd(agent, [{FormatUser, agent.state}, EnrichUserData], %{age: 30},
          apply_state: true
        )

      # State is set
      assert agent.state.age == 30

      # State is updated by FormatUser
      # assert agent.result.formatted_name == "John Doe"

      # State is updated by EnrichUserData
      # assert agent.state.username == "john.doe"
    end
  end
end
