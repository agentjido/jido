defmodule Jido.Action.ToolTest do
  use JidoTest.Case, async: true
  alias Jido.Action.Tool
  alias JidoTest.TestActions

  @moduletag :capture_log

  describe "to_tool/1" do
    test "converts a Jido Workflow to a tool representation" do
      tool = Tool.to_tool(TestActions.BasicAction)

      assert tool.name == "basic_action"
      assert tool.description == "A basic action for testing"
      assert is_function(tool.function, 2)
      assert is_map(tool.parameters_schema)
    end

    test "generates correct parameters schema" do
      tool = Tool.to_tool(TestActions.BasicAction)

      assert tool.parameters_schema == %{
               type: "object",
               properties: %{
                 "value" => %{
                   type: "integer",
                   description: "No description provided."
                 }
               },
               required: ["value"]
             }
    end
  end

  describe "execute_workflow/3" do
    # test "executes the workflow and returns JSON-encoded result" do
    #   params = %{"value" => 42}
    #   context = %{}

    #   assert {:ok, result} = Tool.execute_workflow(TestActions.BasicAction, params, context)
    #   assert Jason.decode!(result) == %{"value" => 42}
    # end

    test "returns JSON-encoded error on failure" do
      params = %{"invalid" => "params"}
      context = %{}

      assert {:error, error} = Tool.execute_workflow(TestActions.BasicAction, params, context)
      assert {:ok, %{"error" => _}} = Jason.decode(error)
    end
  end

  describe "convert_params_using_schema/2" do
    test "converts string parameters to correct types based on schema" do
      params = %{
        "integer" => "42",
        "float" => "3.14",
        "string" => "hello",
        "unspecified" => "value"
      }

      schema = [
        integer: [type: :integer],
        float: [type: :float],
        string: [type: :string]
      ]

      result = Tool.convert_params_using_schema(params, schema)

      assert result == %{
               integer: 42,
               float: 3.14,
               string: "hello"
             }
    end

    test "handles invalid number strings" do
      params = %{
        "integer" => "not_a_number",
        "float" => "invalid"
      }

      schema = [
        integer: [type: :integer],
        float: [type: :float]
      ]

      result = Tool.convert_params_using_schema(params, schema)

      assert result == %{
               integer: "not_a_number",
               float: "invalid"
             }
    end

    test "ignores parameters not in schema" do
      params = %{
        "in_schema" => "42",
        "not_in_schema" => "value"
      }

      schema = [
        in_schema: [type: :integer]
      ]

      result = Tool.convert_params_using_schema(params, schema)

      assert result == %{
               in_schema: 42
             }
    end
  end

  describe "build_parameters_schema/1" do
    test "builds correct schema from workflow schema" do
      schema = TestActions.SchemaAction.schema()
      result = Tool.build_parameters_schema(schema)

      assert result == %{
               type: "object",
               properties: %{
                 "string" => %{type: "string", description: "No description provided."},
                 "integer" => %{type: "integer", description: "No description provided."},
                 "atom" => %{type: "string", description: "No description provided."},
                 "boolean" => %{type: "boolean", description: "No description provided."},
                 "list" => %{type: "array", description: "No description provided."},
                 "keyword_list" => %{type: "object", description: "No description provided."},
                 "map" => %{type: "object", description: "No description provided."},
                 "custom" => %{type: "string", description: "No description provided."}
               },
               required: []
             }
    end
  end

  describe "parameter_to_json_schema/1" do
    test "converts NimbleOptions parameter to JSON Schema" do
      opts = [type: :string, doc: "A test parameter"]
      result = Tool.parameter_to_json_schema(opts)

      assert result == %{
               type: "string",
               description: "A test parameter"
             }
    end

    test "uses default description when doc is not provided" do
      opts = [type: :integer]
      result = Tool.parameter_to_json_schema(opts)

      assert result == %{
               type: "integer",
               description: "No description provided."
             }
    end
  end

  describe "nimble_type_to_json_schema_type/1" do
    test "converts NimbleOptions types to JSON Schema types" do
      assert Tool.nimble_type_to_json_schema_type(:string) == "string"
      assert Tool.nimble_type_to_json_schema_type(:integer) == "integer"
      assert Tool.nimble_type_to_json_schema_type(:float) == "string"
      assert Tool.nimble_type_to_json_schema_type(:boolean) == "boolean"
      assert Tool.nimble_type_to_json_schema_type(:keyword_list) == "object"
      assert Tool.nimble_type_to_json_schema_type(:map) == "object"
      assert Tool.nimble_type_to_json_schema_type({:list, :string}) == "array"
      assert Tool.nimble_type_to_json_schema_type({:map, :string}) == "object"
      assert Tool.nimble_type_to_json_schema_type(:atom) == "string"
    end
  end
end
