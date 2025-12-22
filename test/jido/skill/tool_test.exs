defmodule Jido.Skill.ToolTest do
  use ExUnit.Case, async: true

  alias Jido.Skills.Basic

  describe "to_tools/0" do
    test "converts skill to LLM tool format" do
      tools = Basic.to_tools()

      assert is_list(tools)
      assert length(tools) > 0

      # Check LLM tool format
      Enum.each(tools, fn tool ->
        assert %{name: name, description: desc, parameters: params} = tool
        assert is_binary(name)
        assert is_binary(desc)
        # Parameters may be empty for actions with no schema, or have string/atom keys
        assert is_map(params)

        # Only validate structure if parameters are not empty
        unless params == %{} do
          assert params["type"] == "object" or params[:type] == "object"
          properties = params["properties"] || params[:properties]
          required = params["required"] || params[:required]
          assert is_map(properties)
          assert is_list(required)
        end
      end)
    end
  end

  describe "tool_names/0" do
    test "returns list of tool names" do
      names = Basic.tool_names()

      assert is_list(names)
      assert length(names) > 0
      assert Enum.all?(names, &is_binary/1)
    end
  end

  describe "__skill_metadata__/0" do
    test "returns skill metadata with action info" do
      metadata = Basic.__skill_metadata__()

      assert %{
               name: "basic_tools",
               description: desc,
               category: "Core",
               tags: tags,
               action_count: count,
               action_names: names
             } = metadata

      assert is_binary(desc)
      assert is_list(tags)
      assert is_integer(count)
      assert count > 0
      assert is_list(names)
      assert length(names) == count
    end
  end

  describe "execute_tool/3" do
    test "executes a tool by name" do
      # Test with noop_action tool (should always succeed)
      result = Basic.execute_tool("noop_action", %{}, %{})
      assert {:ok, json_result} = result
      assert is_binary(json_result)

      # Should be valid JSON
      assert {:ok, _parsed} = Jason.decode(json_result)
    end

    test "returns error for non-existent tool" do
      result = Basic.execute_tool("nonexistent", %{}, %{})
      assert {:error, json_error} = result
      assert is_binary(json_error)

      # Should be valid JSON error
      assert {:ok, %{"error" => error_msg}} = Jason.decode(json_error)
      assert String.contains?(error_msg, "not found")
    end
  end
end
