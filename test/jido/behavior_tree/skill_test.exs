defmodule Jido.BehaviorTree.SkillTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Skill, Tree}
  alias Jido.Joi
  alias Jido.BehaviorTree.Nodes.{Action, Wait}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode}

  defmodule AlwaysErrorAction do
    use Jido.Action,
      name: "always_error",
      description: "Returns an error"

    @impl true
    def run(_params, _context) do
      {:error, :forced_error}
    end
  end

  defmodule EmitAction do
    use Jido.Action, name: "bt_tool_emit"

    @impl true
    def run(_params, _context) do
      {:ok, %{output: true}, [Jido.Agent.Directive.emit("bt.tool.output", %{})]}
    end
  end

  test "rejects a tree Action that requests a Directive" do
    skill = Skill.new("no_directives", Tree.new(Action.new(EmitAction)))
    assert {:error, %{message: "Behavior Tree tools cannot return Directives"}} = Skill.run(skill, %{}, %{})
  end

  describe "Skill.new/4" do
    test "creates skill with minimal options" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_skill", tree, "A test skill")

      assert skill.name == "test_skill"
      assert skill.description == "A test skill"
      assert skill.tree == tree
      assert skill.schema == Joi.object(%{})
      assert skill.timeout == 30_000
    end

    test "creates skill with custom options" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = Joi.object(%{input: Joi.string(), count: Joi.integer() |> Joi.default(1)})

      skill =
        Skill.new(
          "custom_skill",
          tree,
          "Custom skill",
          schema: schema,
          timeout: 10_000,
          auto_mode: true
        )

      assert skill.name == "custom_skill"
      assert skill.schema == schema
      assert skill.timeout == 10_000
      assert skill.auto_mode == true
    end
  end

  describe "Skill.to_tool/1" do
    test "converts skill to AI tool definition" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_tool", tree, "Test tool for AI")

      tool_def = Skill.to_tool(skill)

      assert tool_def["name"] == "test_tool"
      assert tool_def["description"] == "Test tool for AI"
      assert is_map(tool_def["parameters"])
    end

    test "converts skill with schema to tool definition" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema =
        Joi.object(%{
          user_id: Joi.integer(description: "User identifier"),
          name: Joi.string(description: "User name") |> Joi.optional()
        })

      skill = Skill.new("user_processor", tree, "Processes user data", schema: schema)

      tool_def = Skill.to_tool(skill)

      assert tool_def["name"] == "user_processor"
      assert tool_def["parameters"]["properties"]["user_id"]["type"] == "integer"
      assert tool_def["parameters"]["properties"]["user_id"]["description"] == "User identifier"
      assert tool_def["parameters"]["properties"]["name"]["type"] == "string"
      assert tool_def["parameters"]["required"] == ["user_id"]
    end
  end

  describe "Skill.run/3" do
    test "executes skill successfully" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("test_skill", tree)

      {:ok, result} = Skill.run(skill, %{}, %{})

      assert is_map(result)
    end

    test "validates input parameters" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema = Joi.object(%{required_param: Joi.string()})

      skill = Skill.new("validation_skill", tree, "", schema: schema)

      # Missing required parameter
      {:error, reason} = Skill.run(skill, %{}, %{})
      assert %Jido.Error.ValidationError{details: %{issues: [%{path: [:required_param]}]}} = reason

      # Valid parameters
      {:ok, _result} = Skill.run(skill, %{required_param: "value"}, %{})
    end

    test "handles skill execution failure" do
      node = FailureNode.new("test failure")
      tree = Tree.new(node)

      skill = Skill.new("failing_skill", tree, "", timeout: 1000)

      {:error, reason} = Skill.run(skill, %{}, %{})
      assert %Jido.BehaviorTree.Error.BehaviorTreeError{} = reason
      assert reason.message == "Behavior tree failed"
    end

    test "validates output with output schema" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      output_schema = Joi.object(%{result: Joi.string()})

      skill =
        Skill.new(
          "output_validation_skill",
          tree,
          "",
          output_schema: output_schema
        )

      assert {:error, %Jido.Error.ValidationError{details: %{issues: [%{path: [:result]}]}}} =
               Skill.run(skill, %{}, %{})
    end

    test "executes with initial blackboard data" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill = Skill.new("blackboard_skill", tree)

      params = %{
        user_id: 123,
        action: "process"
      }

      {:ok, result} = Skill.run(skill, params, %{})

      # The blackboard should contain our input parameters
      assert Map.has_key?(result, :user_id) or Map.has_key?(result, "user_id")
      assert Map.has_key?(result, :action) or Map.has_key?(result, "action")
    end
  end

  describe "Schema conversion" do
    test "converts Joi types to JSON schema" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      schema =
        Joi.object(%{
          string_field: Joi.string(),
          integer_field: Joi.integer(),
          boolean_field: Joi.boolean(),
          map_field: Joi.map(),
          list_field: Joi.list(Joi.string())
        })

      skill = Skill.new("schema_test", tree, "", schema: schema)

      tool_def = Skill.to_tool(skill)
      properties = tool_def["parameters"]["properties"]

      assert properties["string_field"]["type"] == "string"
      assert properties["integer_field"]["type"] == "integer"
      assert properties["boolean_field"]["type"] == "boolean"
      assert properties["map_field"]["type"] == "object"
      assert properties["list_field"]["type"] == "array"
    end
  end

  describe "Auto mode execution" do
    test "completes in auto mode before timeout when tree terminates early" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill =
        Skill.new(
          "auto_skill",
          tree,
          "",
          auto_mode: true,
          timeout: 500,
          interval: 5
        )

      start_time = System.monotonic_time(:millisecond)
      {:ok, _result} = Skill.run(skill, %{}, %{})
      end_time = System.monotonic_time(:millisecond)

      duration = end_time - start_time
      assert duration < 500
    end

    test "returns timeout error in auto mode when tree never completes" do
      tree = Tree.new(Wait.new(1_000))
      skill = Skill.new("auto_timeout", tree, "", auto_mode: true, timeout: 50, interval: 5)

      {:error, reason} = Skill.run(skill, %{}, %{})
      assert %Jido.BehaviorTree.Error.BehaviorTreeError{} = reason
      assert reason.message == "Execution timed out"
    end
  end

  describe "Manual mode execution" do
    test "executes in manual mode with immediate completion" do
      node = SimpleNode.new("test")
      tree = Tree.new(node)

      skill =
        Skill.new(
          "manual_skill",
          tree,
          "",
          auto_mode: false,
          timeout: 5000
        )

      start_time = System.monotonic_time(:millisecond)
      {:ok, _result} = Skill.run(skill, %{}, %{})
      end_time = System.monotonic_time(:millisecond)

      # Should complete quickly since SimpleNode succeeds immediately
      duration = end_time - start_time
      assert duration < 1000
    end

    test "returns timeout error in manual mode when tree does not finish" do
      tree = Tree.new(Wait.new(1_000))
      skill = Skill.new("manual_timeout", tree, "", auto_mode: false, timeout: 50)

      {:error, reason} = Skill.run(skill, %{}, %{})
      assert %Jido.BehaviorTree.Error.BehaviorTreeError{} = reason
      assert reason.message == "Execution timed out"
    end

    test "returns error when action node errors" do
      tree = Tree.new(Action.new(AlwaysErrorAction))
      skill = Skill.new("action_error_skill", tree, "", auto_mode: false, timeout: 1_000)

      {:error, reason} = Skill.run(skill, %{}, %{})
      assert %Jido.BehaviorTree.Error.BehaviorTreeError{} = reason
      assert reason.message == "Behavior tree error"
      assert match?(%Jido.Error.ExecutionError{}, reason.details.reason)
    end
  end
end
