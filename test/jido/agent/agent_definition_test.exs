defmodule JidoTest.AgentDefinitionTest do
  use JidoTest.Case, async: true

  alias JidoTest.TestAgents.{
    MinimalAgent,
    BasicAgent,
    FullFeaturedAgent,
    ValidationAgent,
    CustomRunnerAgent
  }

  alias Jido.Error

  alias JidoTest.TestActions.{
    BasicAction,
    NoSchema,
    EnqueueAction,
    RegisterAction,
    DeregisterAction
  }

  @moduletag :capture_log

  describe "naked new/1" do
    test "returns error for server agent creation" do
      {:error, error} = Jido.Agent.new()
      assert Error.to_map(error).type == :config_error

      assert error.message =~
               "Agents must be implemented as a module utilizing `use Jido.Agent ...`"
    end
  end

  describe "agent creation and initialization" do
    test "creates basic agent with defaults" do
      agent = BasicAgent.new()

      assert agent.id != nil
      assert agent.state.location == :home
      assert agent.state.battery_level == 100
      assert agent.dirty_state? == false
      assert agent.pending_instructions == :queue.new()

      assert agent.actions == [
               BasicAction,
               NoSchema,
               EnqueueAction,
               RegisterAction,
               DeregisterAction
             ]

      assert agent.result == nil
    end

    test "creates agent with custom id" do
      custom_id = "test_id"
      agent = BasicAgent.new(custom_id)
      assert agent.id == custom_id
    end

    test "creates agent with initial state" do
      initial_state = %{location: :garage, battery_level: 50}
      agent = BasicAgent.new("test_id", initial_state)

      assert agent.id == "test_id"
      assert agent.state.location == :garage
      assert agent.state.battery_level == 50
    end

    test "creates agent without schema" do
      agent = MinimalAgent.new()

      assert agent.id != nil
      assert agent.dirty_state? == false
      assert agent.pending_instructions == :queue.new()
      assert agent.actions == []
      assert agent.result == nil
      assert agent.state == %{}
    end

    test "generates unique ids for multiple agents" do
      ids = for _ <- 1..100, do: BasicAgent.new().id
      assert length(Enum.uniq(ids)) == 100
    end

    test "initializes with correct metadata" do
      BasicAgent.new()
      metadata = BasicAgent.__agent_metadata__()

      assert is_map(metadata)
      assert metadata.name == "basic_agent"
      assert metadata.category == nil
      assert is_list(metadata.tags)
      assert is_nil(metadata.vsn)
      assert is_list(metadata.actions)
      assert metadata.runner == Jido.Runner.Simple
    end

    test "initializes with default values from schema" do
      agent = FullFeaturedAgent.new()
      assert agent.state.location == :home
      assert agent.state.battery_level == 100
      assert agent.state.status == :idle
      assert agent.state.config == %{}
      assert agent.state.metadata == %{}
    end

    test "validates required fields in schema" do
      agent = ValidationAgent.new()
      assert Map.has_key?(agent.state, :required_string)
      assert Map.has_key?(agent.state, :nested_map)
    end

    test "merges initial state with schema defaults" do
      initial_state = %{battery_level: 75}
      agent = FullFeaturedAgent.new("test_id", initial_state)

      # From initial state
      assert agent.state.battery_level == 75
      # From schema default
      assert agent.state.location == :home
      # From schema default
      assert agent.state.status == :idle
    end
  end

  describe "basic metadata functionality" do
    test "provides correct metadata for basic agent" do
      assert BasicAgent.name() == "basic_agent"
      assert BasicAgent.description() == nil
      assert BasicAgent.category() == nil
      assert BasicAgent.tags() == []
      assert BasicAgent.vsn() == nil

      assert BasicAgent.actions() == [
               BasicAction,
               NoSchema,
               EnqueueAction,
               RegisterAction,
               DeregisterAction
             ]

      assert BasicAgent.runner() == Jido.Runner.Simple

      metadata = BasicAgent.__agent_metadata__()
      assert metadata == BasicAgent.to_json()
    end

    test "provides correct metadata for full featured agent" do
      assert FullFeaturedAgent.name() == "full_featured_agent"
      assert FullFeaturedAgent.description() == "Tests all agent features"
      assert FullFeaturedAgent.category() == "test"
      assert FullFeaturedAgent.tags() == ["test", "full", "features"]
      assert FullFeaturedAgent.vsn() == "1.0.0"
      assert length(FullFeaturedAgent.actions()) > 0
      assert FullFeaturedAgent.runner() == Jido.Runner.Simple

      metadata = FullFeaturedAgent.__agent_metadata__()
      assert metadata == FullFeaturedAgent.to_json()
    end

    test "provides correct metadata for minimal agent" do
      assert MinimalAgent.name() == "minimal_agent"
      assert MinimalAgent.description() == nil
      assert MinimalAgent.category() == nil
      assert MinimalAgent.tags() == []
      assert MinimalAgent.vsn() == nil
      assert MinimalAgent.schema() == []
      assert MinimalAgent.runner() == Jido.Runner.Simple

      metadata = MinimalAgent.__agent_metadata__()
      assert metadata == MinimalAgent.to_json()
    end
  end

  describe "JSON serialization" do
    test "serializes basic agent metadata correctly" do
      json = BasicAgent.to_json()

      assert is_map(json)
      assert json.name == "basic_agent"
      assert is_list(json.schema)
      assert is_list(json.tags)
      assert is_list(json.actions)
      assert json.runner == Jido.Runner.Simple
      refute Map.has_key?(json, :id)
      refute Map.has_key?(json, :state)
      refute Map.has_key?(json, :pending_instructions)
    end

    test "serializes full featured agent metadata correctly" do
      json = FullFeaturedAgent.to_json()

      assert is_map(json)
      assert json.name == "full_featured_agent"
      assert json.description == "Tests all agent features"
      assert json.category == "test"
      assert json.tags == ["test", "full", "features"]
      assert json.vsn == "1.0.0"
      assert is_list(json.schema)
      assert is_list(json.actions)
      assert json.runner == Jido.Runner.Simple
    end

    test "handles nil values in JSON serialization" do
      json = MinimalAgent.to_json()

      assert is_map(json)
      assert json.name == "minimal_agent"
      assert json.description == nil
      assert json.category == nil
      assert json.tags == []
      assert json.vsn == nil
      assert json.schema == []
      assert json.actions == []
    end
  end

  describe "metadata validation" do
    test "validates agent name format" do
      assert_raise CompileError, ~r/invalid value for :name option/i, fn ->
        Code.eval_string("""
        defmodule InvalidNameAgent do
          use Jido.Agent,
            name: "invalid-name!",
            description: "Agent with invalid name"
        end
        """)
      end
    end

    test "validates tag format" do
      assert_raise CompileError, ~r/invalid configuration/i, fn ->
        Code.eval_string("""
        defmodule InvalidTagsAgent do
          use Jido.Agent,
            name: "invalid_tags_agent",
            tags: ["valid", :invalid, 123]
        end
        """)
      end
    end

    test "handles custom runner module" do
      assert CustomRunnerAgent.runner() == JidoTest.TestRunners.LoggingRunner
      json = CustomRunnerAgent.to_json()
      assert json.runner == JidoTest.TestRunners.LoggingRunner
    end
  end

  describe "schema metadata" do
    test "correctly represents complex schema in metadata" do
      schema = ValidationAgent.schema()
      assert is_list(schema)
      assert Keyword.has_key?(schema, :required_string)
      assert Keyword.has_key?(schema, :optional_integer)
      assert Keyword.has_key?(schema, :nested_map)
      assert Keyword.has_key?(schema, :enum_field)
      assert Keyword.has_key?(schema, :list_field)

      json = ValidationAgent.to_json()
      assert is_list(json.schema)
    end

    test "handles empty schema in metadata" do
      assert MinimalAgent.schema() == []
      json = MinimalAgent.to_json()
      assert json.schema == []
    end
  end

  describe "action metadata" do
    test "correctly lists registered actions" do
      actions = BasicAgent.actions()
      assert Enum.member?(actions, BasicAction)
      assert Enum.member?(actions, NoSchema)
      assert Enum.member?(actions, EnqueueAction)
      assert Enum.member?(actions, RegisterAction)
      assert Enum.member?(actions, DeregisterAction)

      json = BasicAgent.to_json()

      assert json.actions == [
               BasicAction,
               NoSchema,
               EnqueueAction,
               RegisterAction,
               DeregisterAction
             ]
    end

    test "handles duplicate actions in metadata" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.register_action(agent, BasicAction)

      actions = updated.actions
      assert length(actions) == 5
      assert Enum.count(actions, &(&1 == BasicAction)) == 1
    end
  end

  describe "server action registration" do
    test "registers valid actions" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.register_action(agent, JidoTest.TestActions.Add)

      assert Enum.member?(updated.actions, JidoTest.TestActions.Add)
      assert length(updated.actions) == length(agent.actions) + 1
    end

    test "prevents registering invalid modules" do
      agent = BasicAgent.new()
      assert {:error, error} = BasicAgent.register_action(agent, InvalidModule)
      assert Error.to_map(error).type == :validation_error
      assert error.message =~ "Failed to register actions"

      # Original actions list should be unchanged
      assert agent.actions == [
               BasicAction,
               NoSchema,
               EnqueueAction,
               RegisterAction,
               DeregisterAction
             ]
    end

    test "allows registering multiple actions" do
      agent = BasicAgent.new()

      {:ok, updated} =
        BasicAgent.register_action(agent, [
          JidoTest.TestActions.Add,
          JidoTest.TestActions.Multiply
        ])

      assert Enum.member?(updated.actions, JidoTest.TestActions.Add)
      assert Enum.member?(updated.actions, JidoTest.TestActions.Multiply)
      assert length(updated.actions) == length(agent.actions) + 2
    end

    test "lists registered actions in order" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.register_action(agent, JidoTest.TestActions.Add)
      {:ok, updated} = BasicAgent.register_action(updated, JidoTest.TestActions.Multiply)

      actions = BasicAgent.registered_actions(updated)

      # Most recently registered should be first
      assert actions == [
               JidoTest.TestActions.Multiply,
               JidoTest.TestActions.Add,
               BasicAction,
               NoSchema,
               EnqueueAction,
               RegisterAction,
               DeregisterAction
             ]
    end

    test "deregisters existing action" do
      agent = BasicAgent.new()
      {:ok, updated} = BasicAgent.register_action(agent, JidoTest.TestActions.Add)
      {:ok, deregistered} = BasicAgent.deregister_action(updated, JidoTest.TestActions.Add)

      refute Enum.member?(deregistered.actions, JidoTest.TestActions.Add)
      assert length(deregistered.actions) == length(agent.actions)
    end

    test "deregistering non-existent action is noop" do
      agent = BasicAgent.new()
      original_actions = agent.actions
      {:ok, updated} = BasicAgent.deregister_action(agent, JidoTest.TestActions.Add)

      assert updated.actions == original_actions
    end

    test "can deregister and re-register actions" do
      agent = BasicAgent.new()
      {:ok, with_add} = BasicAgent.register_action(agent, JidoTest.TestActions.Add)
      {:ok, removed} = BasicAgent.deregister_action(with_add, JidoTest.TestActions.Add)
      {:ok, readded} = BasicAgent.register_action(removed, JidoTest.TestActions.Add)

      assert Enum.member?(readded.actions, JidoTest.TestActions.Add)
      assert length(readded.actions) == length(agent.actions) + 1
    end
  end
end
