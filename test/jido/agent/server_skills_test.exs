defmodule Jido.Agent.Server.SkillsTest do
  use JidoTest.Case, async: true
  use Mimic

  alias Jido.Agent.Server.Skills
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal.Router
  alias Jido.Instruction
  alias JidoTest.TestAgents.BasicAgent

  alias JidoTest.TestSkills.{
    MockSkill,
    MockSkillWithSchema,
    MockSkillWithMount
  }

  describe "build/2" do
    setup do
      state = %ServerState{
        agent: BasicAgent.new("test"),
        skills: [],
        router: [],
        status: :idle,
        pending_signals: [],
        max_queue_size: 1000,
        mode: :default,
        dispatch: nil,
        child_supervisor: nil,
        current_signal: nil,
        current_signal_type: nil,
        log_level: :info,
        registry: nil
      }

      {:ok, state: state}
    end

    test "successfully builds state with a single skill", %{state: state} do
      opts = [skills: [MockSkill]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills
      assert Keyword.get(updated_opts, :routes) == MockSkill.router()
      assert [MockSkill.child_spec()] == Keyword.get(updated_opts, :child_specs)
    end

    test "handles multiple skills", %{state: state} do
      opts = [skills: [MockSkill, MockSkill]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill, MockSkill] == updated_state.skills

      expected_routes = MockSkill.router() ++ MockSkill.router()
      assert Keyword.get(updated_opts, :routes) == expected_routes

      expected_child_specs = [MockSkill.child_spec(), MockSkill.child_spec()]
      assert Keyword.get(updated_opts, :child_specs) == expected_child_specs
    end

    test "returns original state when no skills provided", %{state: state} do
      opts = []
      assert {:ok, ^state, ^opts} = Skills.build(state, opts)
    end

    test "returns original state when skills is nil", %{state: state} do
      opts = [skills: nil]
      assert {:ok, ^state, ^opts} = Skills.build(state, opts)
    end

    test "returns error for invalid skills input", %{state: state} do
      opts = [skills: :not_a_list]
      assert {:error, "Skills must be a list, got: :not_a_list"} = Skills.build(state, opts)
    end

    test "accumulates routes and child_specs correctly", %{state: state} do
      existing_routes = [
        %Router.Route{
          path: "existing.path",
          target: %Instruction{action: :existing},
          priority: 0
        }
      ]

      existing_child_spec = %{id: :existing, start: {Module, :start_link, []}}

      opts = [
        skills: [MockSkill],
        routes: existing_routes,
        child_specs: [existing_child_spec]
      ]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills

      # Check routes are combined
      assert existing_routes ++ MockSkill.router() == Keyword.get(updated_opts, :routes)

      # Check child_specs are combined
      assert [MockSkill.child_spec(), existing_child_spec] ==
               Keyword.get(updated_opts, :child_specs)
    end

    test "validates skill options and stores them in agent state", %{state: state} do
      opts = [
        skills: [MockSkillWithSchema],
        mock_skill_with_schema: [api_key: "test_key", timeout: 10_000]
      ]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithSchema] == updated_state.skills

      # Check that the validated options are stored in the agent state
      stored_opts = updated_state.agent.state[:mock_skill_with_schema]
      assert Keyword.get(stored_opts, :api_key) == "test_key"
      assert Keyword.get(stored_opts, :timeout) == 10_000
    end

    test "returns error when skill options validation fails", %{state: state} do
      opts = [
        skills: [MockSkillWithSchema],
        # Missing required api_key
        mock_skill_with_schema: [timeout: 10_000]
      ]

      assert {:error, error_message} = Skills.build(state, opts)

      assert String.contains?(
               error_message,
               "Failed to validate options for skill mock_skill_with_schema"
             )
    end

    test "uses default values for skill options when not provided", %{state: state} do
      opts = [
        skills: [MockSkillWithSchema],
        mock_skill_with_schema: [api_key: "test_key"]
      ]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)

      # Check that the default timeout value is used
      stored_opts = updated_state.agent.state[:mock_skill_with_schema]
      assert Keyword.get(stored_opts, :api_key) == "test_key"
      assert Keyword.get(stored_opts, :timeout) == 5000
    end

    test "calls mount callback and transforms agent", %{state: state} do
      opts = [skills: [MockSkillWithMount]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithMount] == updated_state.skills

      # Check that the mount callback was called and transformed the agent
      assert updated_state.agent.state[:mount_called] == true

      # Verify the action was registered
      assert Enum.member?(updated_state.agent.actions, JidoTest.TestActions.BasicAction)
    end
  end
end
