Code.require_file("../support/rag_tool_client.ex", __DIR__)
Code.require_file("agentic_rag_tool.ex", __DIR__)

defmodule Jido.Examples.RAG.AgenticToolTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.RAG.Agentic.Agent
  alias Jido.Examples.RAG.ToolClient

  test "ReAct selects the retrieval Action and returns its citation" do
    source = Agent.instantiate!(id: "agentic-rag-1")
    request = Agent.request_signal!(%{input: "What is the retention limit?"})

    assert {:ok, candidate, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(source, request, context: %{jido_ai_inference_client: ToolClient})

    assert reply.data.status == :completed
    assert reply.data.output == "The policy limit is 30 days [doc-1]."
    assert reply.data.model_calls == 2
    assert reply.data.tool_calls == 1
    assert [%{tool: %{name: "rag_lookup_policy"}, status: :ok}] = reply.data.tool_attempts

    tool_entry =
      Enum.find(candidate.state.session.thread.entries, fn entry ->
        entry.kind == :ai_message and entry.payload["role"] == "tool"
      end)

    assert get_in(tool_entry.payload, ["output", "source_id"]) == "doc-1"
    assert get_in(tool_entry.payload, ["output", "revision"]) == 3
  end
end
