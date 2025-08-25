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
    MockSkillWithMount,
    MockSkillWithListChildSpecs,
    MockSkillWithActions,
    MockSkillWithActionsAndMount
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

    test "correctly handles skills that return list of child specs", %{state: state} do
      # Create a mock skill that returns a list of child specs

      opts = [skills: [MockSkillWithListChildSpecs]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithListChildSpecs] == updated_state.skills

      # Check that child_specs are properly flattened (not nested)
      child_specs = Keyword.get(updated_opts, :child_specs)
      assert is_list(child_specs)
      assert length(child_specs) == 2

      # Verify they are proper child specs (not nested lists)
      Enum.each(child_specs, fn spec ->
        assert is_tuple(spec)
        assert tuple_size(spec) == 2
      end)
    end

    test "correctly handles skills that return single child spec", %{state: state} do
      # Use MockSkill which returns a single child spec
      opts = [skills: [MockSkill]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills

      # Check that single child_spec is properly wrapped in a list
      child_specs = Keyword.get(updated_opts, :child_specs)
      assert is_list(child_specs)
      assert length(child_specs) == 1

      # Verify it's a proper child spec (not nested list)
      [child_spec] = child_specs
      assert is_map(child_spec)
      assert Map.has_key?(child_spec, :id)
      assert Map.has_key?(child_spec, :start)
    end

    test "handles mixed skills with different child_spec return types", %{state: state} do
      opts = [skills: [MockSkill, MockSkillWithListChildSpecs]]

      assert {:ok, updated_state, updated_opts} = Skills.build(state, opts)
      assert length(updated_state.skills) == 2

      # Check that all child_specs are properly flattened
      child_specs = Keyword.get(updated_opts, :child_specs)
      assert is_list(child_specs)
      # 1 from MockSkill + 2 from MockSkillWithListChildSpecs
      assert length(child_specs) == 3

      # Verify none are nested lists
      Enum.each(child_specs, fn spec ->
        refute is_list(spec)
        assert is_tuple(spec) or is_map(spec)
      end)
    end

    test "registers skill actions with agent", %{state: state} do
      opts = [skills: [MockSkillWithActions]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithActions] == updated_state.skills

      # Check that the skill's actions were registered with the agent
      agent_actions = updated_state.agent.actions
      assert JidoTest.TestActions.BasicAction in agent_actions
      assert JidoTest.TestActions.ErrorAction in agent_actions
    end

    test "registers actions from multiple skills", %{state: state} do
      opts = [skills: [MockSkillWithActions, MockSkillWithMount]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert length(updated_state.skills) == 2

      # Check that actions from both skills are registered
      agent_actions = updated_state.agent.actions
      assert JidoTest.TestActions.BasicAction in agent_actions
      assert JidoTest.TestActions.ErrorAction in agent_actions
    end

    test "does not register duplicate actions from multiple skills", %{state: state} do
      # Both skills register BasicAction
      opts = [skills: [MockSkillWithActions, MockSkillWithActionsAndMount]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert length(updated_state.skills) == 2

      # Check that BasicAction is only present once
      agent_actions = updated_state.agent.actions
      basic_action_count = Enum.count(agent_actions, &(&1 == JidoTest.TestActions.BasicAction))
      assert basic_action_count == 1

      # But ErrorAction should be present (from both skills)
      error_action_count = Enum.count(agent_actions, &(&1 == JidoTest.TestActions.ErrorAction))
      assert error_action_count == 1
    end

    test "combines skill actions with mount callback actions", %{state: state} do
      opts = [skills: [MockSkillWithActionsAndMount]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithActionsAndMount] == updated_state.skills

      # Check that actions from both configuration and mount callback are registered
      agent_actions = updated_state.agent.actions
      assert JidoTest.TestActions.BasicAction in agent_actions
      assert JidoTest.TestActions.ErrorAction in agent_actions

      # Check that the mount callback was called
      assert updated_state.agent.state[:mount_called] == true
    end

    test "handles skills with no actions gracefully", %{state: state} do
      # Store original actions before processing skill
      original_actions = state.agent.actions
      original_action_count = length(original_actions)

      opts = [skills: [MockSkill]]

      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkill] == updated_state.skills

      # MockSkill has no actions, so no additional actions should be registered
      # (only existing actions from the basic agent should remain)
      assert length(updated_state.agent.actions) == original_action_count
      assert updated_state.agent.actions == original_actions
      refute Enum.any?(updated_state.agent.actions -- original_actions)
    end

    test "validates skill actions are valid modules", %{state: state} do
      # This test ensures that the validate_module function works correctly
      # We'll test this indirectly by ensuring MockSkillWithActions compiles without errors
      # since it references real test action modules

      opts = [skills: [MockSkillWithActions]]
      assert {:ok, updated_state, _updated_opts} = Skills.build(state, opts)
      assert [MockSkillWithActions] == updated_state.skills
    end
  end
end
