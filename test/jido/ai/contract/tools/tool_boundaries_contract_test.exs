defmodule Jido.AI.Contract.ToolBoundariesTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.{ToolResult, ToolSource, Toolset}
  alias Jido.AITest.Tools

  defmodule VariableSource do
    @behaviour Jido.AI.ToolSource

    @impl true
    def list_tools(%{list: :tool_struct}, _context) do
      {:ok, tool} =
        ReqLLM.Tool.new(
          name: "source_tool",
          description: "Source tool",
          parameter_schema: [value: [type: :string, required: true]],
          callback: {Jido.AI.ToolSource, :execution_boundary}
        )

      {:ok, [tool]}
    end

    def list_tools(%{list: :invalid_result}, _context), do: :invalid
    def list_tools(%{list: :invalid_definitions}, _context), do: {:ok, :invalid}
    def list_tools(%{list: :invalid_definition}, _context), do: {:ok, [:invalid]}
    def list_tools(%{list: :raise}, _context), do: raise("source list failed")
    def list_tools(%{list: :throw}, _context), do: throw(:source_list_failed)
    def list_tools(_config, _context), do: {:ok, []}

    @impl true
    def run_tool(_call, %{run: :ok}, _context), do: {:ok, %{value: 1}}
    def run_tool(_call, %{run: :effects}, _context), do: {:ok, %{value: 1}, [%{kind: :effect}]}
    def run_tool(_call, %{run: :improper_effects}, _context), do: {:ok, :value, [:effect | :tail]}
    def run_tool(_call, %{run: :error}, _context), do: {:error, :failed}
    def run_tool(_call, %{run: :error_effects}, _context), do: {:error, :failed, [:ignored]}
    def run_tool(_call, %{run: :invalid}, _context), do: :invalid
    def run_tool(_call, %{run: :raise}, _context), do: raise("source run failed")
    def run_tool(_call, %{run: :throw}, _context), do: throw(:source_run_failed)
  end

  @tag obligation: "jido_ai.tools.I6"
  test "tool result normalization handles content, truncation, and invalid local values" do
    result = %ReqLLM.ToolResult{
      output: %{value: 1},
      content: [ReqLLM.Message.ContentPart.text("one")],
      metadata: %{source: "contract"}
    }

    assert %{value: %{__jido_ai_tool_result__: 1}} =
             ToolResult.portable_outcome(%{status: :ok, value: result})

    assert %{error: %{__jido_ai_tool_result__: 1}} =
             ToolResult.portable_outcome(%{status: :error, error: result})

    assert %{status: :ok, value: :plain} = ToolResult.portable_outcome(%{status: :ok, value: :plain})

    portable = ToolResult.portable_outcome(%{status: :ok, value: result}).value

    assert %{status: :ok, content_parts: [%{"type" => "text"}]} =
             ToolResult.normalize(%{status: :ok, value: portable}, 1_024)

    string_portable = Map.new(portable, fn {key, value} -> {Atom.to_string(key), value} end)

    assert %{status: :ok, content_parts: [%{"type" => "text"}]} =
             ToolResult.normalize(%{status: :ok, value: string_portable}, 1_024)

    assert %{status: :error, error: %{"type" => "contract_error"}} =
             ToolResult.normalize(
               %{
                 status: :error,
                 error: %ReqLLM.ToolResult{
                   output: %{type: :contract_error, message: "failed", retryable?: true},
                   content: [ReqLLM.Message.ContentPart.text("failed")]
                 }
               },
               1_024
             )

    assert %{status: :error, error: %{"type" => "tool_error", "message" => "tool action failed"}} =
             ToolResult.normalize(%{status: :error, error: %{}}, 1_024)

    assert %{status: :error, error: %{"type" => "invalid_tool_result"}} =
             ToolResult.normalize(:invalid, 1_024)

    assert {%{"status" => "error"}, %{bytes: nil}} = ToolResult.project(%{pid: self()}, 1_024)

    assert {%{"status" => "truncated", "max_bytes" => 8}, %{truncated: true}} =
             ToolResult.project(%{large: String.duplicate("x", 100)}, 8)

    invalid_content = %{__jido_ai_tool_result__: 1, content: :invalid, output: nil, metadata: %{}}

    assert %{status: :error, error: %{"type" => "invalid_tool_result"}} =
             ToolResult.normalize(%{status: :ok, value: invalid_content}, 1_024)

    oversized = %ReqLLM.ToolResult{
      output: %{large: String.duplicate("x", 100)},
      content: [ReqLLM.Message.ContentPart.text(String.duplicate("x", 100))]
    }

    assert %{content_parts: nil, model_content: %{"status" => "truncated"}} =
             ToolResult.normalize(%{status: :ok, value: oversized}, 16)
  end

  @tag obligation: ["jido_ai.tools.I2", "jido_ai.tools.I5"]
  test "dynamic source loading and execution reject every invalid boundary shape" do
    assert ToolSource.from_context(%{}) == []
    assert ToolSource.from_context(%{jido_ai_tool_sources: :invalid}) == []
    assert {:error, :invalid_tool_sources} = ToolSource.load(%{jido_ai_tool_sources: :invalid})

    assert {:error, {:invalid_tool_source, :invalid}} =
             ToolSource.load(%{jido_ai_tool_sources: [:invalid]})

    assert {:error, {:invalid_tool_source, String}} = ToolSource.load(%{jido_ai_tool_sources: [String]})

    assert {:error, {:invalid_tool_source_result, VariableSource, :invalid}} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :invalid_result}}]})

    assert {:error, :invalid_tool_source_definitions} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :invalid_definitions}}]})

    assert {:error, :invalid_tool_source_definition} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :invalid_definition}}]})

    assert {:error, {:tool_source_failed, VariableSource, "source list failed"}} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :raise}}]})

    assert {:error, {:tool_source_failed, VariableSource, {:throw, :source_list_failed}}} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :throw}}]})

    assert {:ok, [tool]} =
             ToolSource.load(%{jido_ai_tool_sources: [{VariableSource, %{list: :tool_struct}}]})

    assert {:ok, definition} = ToolSource.definition(tool)
    assert definition.name == "source_tool"
    assert {:ok, %{value: "ok"}} = ToolSource.validate_input(tool, %{"value" => "ok"})
    assert {:error, _reason} = ToolSource.validate_input(tool, %{})
    assert ToolSource.execution_boundary(%{}) == {:error, :tool_must_run_in_agent_graph}

    call = %{id: "source-1", name: "source_tool", arguments: %{value: "ok"}}
    executor = %{kind: :source, module: VariableSource, config: %{run: :ok}}
    assert {:ok, %{value: 1}} = ToolSource.run(executor, call, %{})
    assert {:ok, %{value: 1}, [%{kind: :effect}]} = ToolSource.run(%{executor | config: %{run: :effects}}, call, %{})

    assert {:error, :invalid_tool_source_effects} =
             ToolSource.run(%{executor | config: %{run: :improper_effects}}, call, %{})

    assert {:error, :failed} = ToolSource.run(%{executor | config: %{run: :error}}, call, %{})
    assert {:error, :failed} = ToolSource.run(%{executor | config: %{run: :error_effects}}, call, %{})

    assert {:error, {:invalid_tool_source_result, :invalid}} =
             ToolSource.run(%{executor | config: %{run: :invalid}}, call, %{})

    assert {:error, %RuntimeError{message: "source run failed"}} =
             ToolSource.run(%{executor | config: %{run: :raise}}, call, %{})

    assert {:error, {:throw, :source_run_failed}} = ToolSource.run(%{executor | config: %{run: :throw}}, call, %{})
  end

  @tag obligation: ["jido_ai.tools.I1", "jido_ai.tools.I3", "jido_ai.tools.I4"]
  test "Toolset policy, definitions, and call resolution share one boundary" do
    assert {:error, :invalid_toolset} = Toolset.validate(:invalid)
    assert {:error, {:invalid_tool, :invalid}} = Toolset.validate([:invalid])
    assert Toolset.execution_boundary(%{}) == {:error, :tool_must_run_in_agent_graph}

    input = %Jido.Plugin.Input{prepared: [Tools.Add], runtime: nil}
    assert Toolset.from_context(%{plugin_inputs: %{Jido.AI.Agent.Plugin => input}}) == [Tools.Add]
    assert Toolset.from_context(%{}) == []
    assert Toolset.names([Tools.Add, Tools.Multiply]) == ["add", "multiply"]

    assert {:ok, [%ReqLLM.Tool{name: "add"}, %ReqLLM.Tool{name: "multiply"}]} =
             Toolset.definitions([Tools.Add, Tools.Multiply])

    assert {:error, {:invalid_runtime_tool, :invalid}} = Toolset.definitions([:invalid])
    assert {:error, :duplicate_tools} = Toolset.definitions([Tools.Add, Tools.Add])
    assert {:error, :invalid_tool_policy} = Toolset.select(:invalid, %{})
    assert {:error, :invalid_tool_policy} = Toolset.select([Tools.Add], %{visible: :invalid})
    assert {:error, :duplicate_tool_policy_names} = Toolset.select([Tools.Add], %{visible: ["add", "add"]})
    assert {:error, {:invalid_tool_requirement, :always}} = Toolset.select([Tools.Add], %{requirement: :always})

    assert {:error, {:tool_requirement_without_visible_tools, :required}} =
             Toolset.select([Tools.Add], %{hidden: ["add"], requirement: :required})

    assert {:error, {:review_tool_not_visible, "add"}} =
             Toolset.select([Tools.Add], %{hidden: ["add"], review: ["add"]})

    assert {:ok, %{tools: [], requirement: :disabled}} =
             Toolset.select([Tools.Add], %{requirement: :disabled})

    assert Toolset.provider_tool_choice(:disabled, 0, [Tools.Add]) == :none
    assert Toolset.provider_tool_choice(:optional, 0, []) == nil
    assert Toolset.provider_tool_choice(:optional, 0, [Tools.Add]) == nil
    assert Toolset.provider_tool_choice(:required, 0, [Tools.Add]) == :required
    assert Toolset.provider_tool_choice(:required, 1, [Tools.Add]) == :auto
    assert Toolset.provider_tool_choice(:per_turn, 1, [Tools.Add]) == :required
    refute Toolset.requirement_satisfied?(:required, 0, [Tools.Add])
    refute Toolset.requirement_satisfied?(:per_turn, 1, [Tools.Add])
    assert Toolset.requirement_satisfied?(:optional, 0, [Tools.Add])

    assert {:error, {:unknown_tool, "missing"}} =
             Toolset.resolve_call([Tools.Add], %{name: "missing"})

    assert {:error, :invalid_tool_call} = Toolset.resolve_call([Tools.Add], %{})
  end
end
