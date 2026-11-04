Code.require_file("../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(JidoTest.Examples.AIModel), do: Code.require_file("../../support/ai_model.exs", __DIR__)

JidoTest.Examples.Loader.require_source!("15_ai_basics/15_02_tool_flow/agent.ex")

defmodule JidoTest.Examples.AI.ToolFlowTest do
  use JidoTest.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("15_ai_basics/15_02_tool_flow/agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.ToolFlow
  alias JidoTest.Examples.AIModel

  test "the Action and Flow have the same validated calculation" do
    assert {:ok, %{product: 12}} = Jido.Exec.run(ToolFlow.Multiply, %{left: 3, right: 4}, %{})
    assert {:ok, %{product: 12}} = Jido.Exec.run(ToolFlow.MultiplyFlow, %{left: 3, right: 4}, %{})
  end

  test "one Flow tool call runs inside the deterministic ReAct round" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      calls = [ReqLLM.ToolCall.new("multiply-flow-1", "multiply_flow", ~s({"left":6,"right":7}))]
      {:ok, AIModel.tool_response(model, context, calls)}
    end)

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, AIModel.text_response(model, context, "The product is 42.")}
    end)

    agent = ToolFlow.Agent.instantiate!(id: unique_id("tool-flow"))

    assert {:ok, _next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             ToolFlow.Agent.cmd(agent, ToolFlow.Agent.request_signal!(%{input: "Multiply 6 by 7."}))

    assert reply.data.output == "The product is 42."
    assert reply.data.tool_calls == 1
  end

  test "preflight can hide one declared tool" do
    assert {:ok, %{tools: tools, params: params}} =
             ToolFlow.Agent.preflight(%{
               input: "Use one tool",
               tool_policy: %{visible: ["multiply"], hidden: ["multiply_flow"]}
             })

    assert Enum.map(tools, & &1.name()) == ["multiply", "multiply_flow"]
    assert params.tool_policy.visible == ["multiply"]
    assert params.tool_policy.hidden == ["multiply_flow"]
  end
end
