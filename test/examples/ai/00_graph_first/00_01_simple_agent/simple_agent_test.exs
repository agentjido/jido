Code.require_file("../../../support/loader.exs", __DIR__)
unless Code.ensure_loaded?(JidoTest.Examples.AIModel), do: Code.require_file("../../../support/ai_model.exs", __DIR__)
JidoTest.Examples.Loader.require_source!("ai/00_graph_first/00_01_simple_agent/simple_agent.ex")

defmodule JidoTest.Examples.AI.SimpleAgentTest do
  use JidoTest.Case, async: false
  import Mimic

  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("ai/00_graph_first/00_01_simple_agent/simple_agent.ex")
    :ok
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.SimpleAgent
  alias JidoTest.Examples.AIModel

  test "the Agent exposes its root graph and ordered tools" do
    assert SimpleAgent.reasoning() == Jido.AI.Reasoning.ReAct

    assert %{tools: tools, flow: %Jido.Flow{}} = SimpleAgent.explain()
    assert tools == [Jido.Examples.AI.Tools.Add, Jido.Examples.AI.Tools.Multiply]
    assert SimpleAgent.route_executable!("jido.ai.request") == Jido.AI.Reasoning.ReAct
  end

  test "preflight validates and compiles without a provider" do
    assert {:ok, %{workflow: %Runic.Workflow{}, params: params}} =
             SimpleAgent.preflight(%{input: "Add two values"})

    assert params.input == "Add two values"
    assert {:error, _} = SimpleAgent.preflight(%{})
  end

  test "one deterministic tool round commits the final answer" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      calls = [
        ReqLLM.ToolCall.new("add-1", "add", ~s({"left":2,"right":3})),
        ReqLLM.ToolCall.new("multiply-1", "multiply", ~s({"left":4,"right":5}))
      ]

      {:ok, AIModel.tool_response(model, context, calls)}
    end)

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, AIModel.text_response(model, context, "Results: 5 and 20.")}
    end)

    agent = SimpleAgent.instantiate!(id: unique_id("simple-ai"))
    request = SimpleAgent.request_signal!(%{input: "Use both tools."})

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             SimpleAgent.cmd(agent, request)

    assert reply.data.output == "Results: 5 and 20."
    assert reply.data.tool_calls == 2
    assert reply.data.tool_rounds == 1
    assert next.state.session.thread.rev > 0
  end
end
