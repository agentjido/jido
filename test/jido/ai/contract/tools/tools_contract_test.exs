defmodule Jido.AI.Contract.ToolsTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.{ToolResult, ToolSource, Toolset}
  alias Jido.AITest.{DynamicToolSource, Tools}

  @tag obligation: ["jido_ai.tools.I1", "jido_ai.tools.I3", "jido_ai.tools.I4"]
  test "static tools form a protected allowlist and calls validate before use" do
    assert :ok = Toolset.validate([Tools.Add, Tools.AddFlow, Tools.Multiply])
    assert {:error, :duplicate_tools} = Toolset.validate([Tools.Add, Tools.Add])

    assert {:ok, selection} =
             Toolset.select([Tools.Add, Tools.Multiply], %{
               visible: ["add"],
               review: ["add"]
             })

    assert selection.tools == [Tools.Add]

    assert {:error, {:unknown_tool, "delete"}} =
             Toolset.select([Tools.Add], %{visible: ["delete"]})

    assert {:ok, call} =
             Toolset.resolve_call([Tools.Add], %{
               id: "add-1",
               name: "add",
               arguments: %{"left" => 2, "right" => 3}
             })

    assert call.params == %{left: 2, right: 3}

    assert {:error, _reason} =
             Toolset.validate_call([Tools.Add], %{
               id: "add-2",
               name: "add",
               arguments: %{"left" => "bad", "right" => 3}
             })

    assert {:ok, flow_call} =
             Toolset.resolve_call([Tools.AddFlow], %{
               id: "flow-1",
               name: "add_flow",
               arguments: %{"left" => 2, "right" => 3}
             })

    assert flow_call.executor == %{kind: :flow, target: Tools.AddFlow}
    assert flow_call.tool.kind == :flow
    assert flow_call.tool.flow == Atom.to_string(Tools.AddFlow)
  end

  @tag obligation: ["jido_ai.tools.I2", "jido_ai.tools.I5"]
  test "dynamic tools load only from trusted portable source context" do
    assert {:ok, []} = ToolSource.load(%{})

    context = %{
      jido_ai_tool_sources: [{DynamicToolSource, %{prefix: "contract"}}]
    }

    assert {:ok, [tool]} = ToolSource.load(context)
    assert tool.name == "dynamic_echo"

    assert ToolSource.identity(tool) == %{
             kind: :source,
             name: "dynamic_echo",
             source: "Elixir.Jido.AITest.DynamicToolSource"
           }

    assert {:ok, %{echo: "contract:hello"}} =
             ToolSource.run(
               ToolSource.executor(tool),
               %{id: "echo-1", name: "dynamic_echo", arguments: %{text: "hello"}},
               context
             )

    assert {:error, _reason} =
             ToolSource.load(%{jido_ai_tool_sources: [{DynamicToolSource, self()}]})
  end

  @tag obligation: ["jido_ai.tools.I2", "jido_ai.tools.I5"]
  test "dynamic tools expose one complete portable source record" do
    context = %{jido_ai_tool_sources: [{DynamicToolSource, %{prefix: "contract"}}]}

    assert {:ok,
            [
              %{
                kind: :source,
                name: "dynamic_echo",
                description: "Echo text through a runtime tool source.",
                parameter_schema: %{
                  "type" => "object",
                  "properties" => %{"text" => %{"type" => "string"}},
                  "required" => ["text"],
                  "additionalProperties" => false
                },
                strict: true,
                provider_options: %{},
                source: %{module: DynamicToolSource, config: %{prefix: "contract"}}
              } = tool
            ]} = ToolSource.load(context)

    assert ToolSource.identity(tool) == %{
             kind: :source,
             name: "dynamic_echo",
             source: "Elixir.Jido.AITest.DynamicToolSource"
           }

    assert ToolSource.executor(tool) == %{
             kind: :source,
             module: DynamicToolSource,
             config: %{prefix: "contract"}
           }
  end

  @tag obligation: "jido_ai.tools.I6"
  test "tool results preserve valid content parts and bound model content" do
    rich = %ReqLLM.ToolResult{
      output: %{asset_id: "asset-1"},
      content: [
        ReqLLM.Message.ContentPart.text("Chart ready"),
        ReqLLM.Message.ContentPart.image_url("https://example.com/chart.png")
      ],
      metadata: %{source: "contract"}
    }

    normalized = ToolResult.normalize(%{status: :ok, value: rich}, 4_096)
    assert Enum.map(normalized.content_parts, & &1["type"]) == ["text", "image_url"]
    assert normalized.result_metadata == %{"source" => "contract"}

    local = %{private: String.duplicate("large", 100)}
    bounded = ToolResult.normalize(%{status: :ok, value: local}, 64)
    assert bounded.value == local
    assert bounded.model_content["status"] == "truncated"
    assert bounded.metadata.truncated
  end
end
