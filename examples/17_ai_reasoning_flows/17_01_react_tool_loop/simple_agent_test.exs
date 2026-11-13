Code.require_file("../../support/offline_inference_client.ex", __DIR__)
Code.require_file("react_offline_client.ex", __DIR__)
Code.require_file("simple_agent.ex", __DIR__)

defmodule Jido.Examples.AI.SimpleAgentTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Examples.AI.{ReActOfflineClient, SimpleAgent}

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
    agent =
      SimpleAgent.instantiate!(id: "simple-ai-#{System.unique_integer([:positive])}")

    request = SimpleAgent.request_signal!(%{input: "Use both tools."})

    assert {:ok, next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             SimpleAgent.cmd(agent, request, context: %{jido_ai_inference_client: ReActOfflineClient})

    assert reply.data.output == "Results: 5 and 20."
    assert reply.data.tool_calls == 2
    assert reply.data.tool_rounds == 1
    assert next.state.session.thread.rev > 0
  end
end
