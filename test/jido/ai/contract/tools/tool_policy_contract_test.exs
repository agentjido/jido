defmodule Jido.AI.Contract.ToolPolicyTest do
  use Covenant.Case, component: "jido_ai.tools", async: true

  alias Jido.AI.{ToolResult, Toolset}
  alias Jido.AITest.Tools

  @tag obligation: ["jido_ai.tools.I1", "jido_ai.tools.I3", "jido_ai.tools.I4"]
  test "tool selection can only narrow the Agent allowlist" do
    actions = [Tools.Add, Tools.Multiply]

    assert {:ok, selection} =
             Toolset.select(actions, %{
               visible: ["multiply", "add"],
               hidden: ["multiply"],
               review: ["add"],
               requirement: :required,
               reason: "only addition is approved"
             })

    assert selection.actions == [Tools.Add]
    assert selection.visible == ["add"]
    assert selection.hidden == ["multiply"]
    assert selection.review == ["add"]
    assert selection.requirement == :required

    assert {:error, {:unknown_tool, "delete_everything"}} =
             Toolset.select(actions, %{visible: ["delete_everything"]})
  end

  @tag obligation: "jido_ai.tools.I4"
  test "semantic tool requirements lower without provider policy in request data" do
    actions = [Tools.Add]

    assert Toolset.provider_tool_choice(:optional, 0, actions) == nil
    assert Toolset.provider_tool_choice(:required, 0, actions) == :required
    assert Toolset.provider_tool_choice(:required, 1, actions) == :auto
    assert Toolset.provider_tool_choice(:per_turn, 1, actions) == :required
    assert Toolset.provider_tool_choice(:disabled, 0, actions) == :none

    refute Toolset.requirement_satisfied?(:required, 0, actions)
    assert Toolset.requirement_satisfied?(:required, 1, actions)
  end

  @tag obligation: "jido_ai.tools.I6"
  test "tool results keep the local value separate from bounded model content" do
    local_value = %{content: String.duplicate("private", 100)}
    result = ToolResult.normalize(%{status: :ok, value: local_value}, 256)

    assert result.value == local_value
    assert result.model_content["status"] == "truncated"
    assert result.metadata.truncated
    refute inspect(result.model_content) =~ String.duplicate("private", 10)
  end

  @tag obligation: ["jido_ai.tools.I3", "jido_ai.tools.I4"]
  test "tool selection and call resolution return complete canonical records" do
    assert {:ok,
            %{
              tools: [Tools.Add],
              actions: [Tools.Add],
              visible: ["add"],
              hidden: ["multiply"],
              review: ["add"],
              requirement: :required,
              reason: "approved"
            }} =
             Toolset.select([Tools.Add, Tools.Multiply], %{
               visible: ["add"],
               review: ["add"],
               requirement: :required,
               reason: "approved"
             })

    call = %{id: "call-1", name: "add", arguments: %{"left" => 2, "right" => 3}}

    assert {:ok,
            %{
              id: "call-1",
              name: "add",
              arguments: %{"left" => 2, "right" => 3},
              params: %{left: 2, right: 3},
              executor: %{kind: :action, target: Tools.Add},
              tool: %{
                kind: :action,
                name: "add",
                id: "jido.ai/examples/tools/add",
                vsn: 1,
                action: "Elixir.Jido.AITest.Tools.Add"
              },
              description: "Add two numbers."
            }} = Toolset.resolve_call([Tools.Add], call)
  end

  @tag obligation: "jido_ai.tools.I6"
  test "tool result projection returns complete bounded records" do
    value = %{answer: 42}

    assert %{
             status: :ok,
             value: ^value,
             model_content: %{"answer" => 42},
             content_parts: nil,
             result_metadata: %{},
             error: nil,
             metadata: %{bytes: 13, max_bytes: 128, truncated: false}
           } = ToolResult.normalize(%{status: :ok, value: value}, 128)

    assert {%{"answer" => 42}, %{bytes: 13, max_bytes: 128, truncated: false}} =
             ToolResult.project(value, 128)

    large = %{answer: String.duplicate("x", 20)}

    assert {
             %{
               "status" => "truncated",
               "message" => "tool result exceeded the model-content limit",
               "original_bytes" => 33,
               "max_bytes" => 8
             },
             %{bytes: 33, max_bytes: 8, truncated: true}
           } = ToolResult.project(large, 8)

    assert {
             %{
               "status" => "error",
               "error" => %{
                 "type" => "invalid_tool_result",
                 "message" => "tool result is not JSON-compatible",
                 "retryable" => false
               }
             },
             %{bytes: nil, max_bytes: 128, truncated: false}
           } = ToolResult.project(%{pid: self()}, 128)
  end
end
