Code.require_file("agent.ex", __DIR__)

defmodule Jido.Examples.AI.StructuredOutputTest do
  use Jido.Test.Case, async: false
  import Mimic

  @moduletag :integration

  setup :set_mimic_global
  setup :verify_on_exit!

  alias Jido.Examples.AI.StructuredOutput.Agent
  alias Jido.Test.Examples.AIModel

  test "preflight carries the strict output schema" do
    assert {:ok, %{params: %{output_schema: schema}}} = Agent.preflight(%{input: "Assess OTP"})
    assert schema == Agent.answer_schema()
    assert schema["additionalProperties"] == false
  end

  test "the structured model object is the completed output" do
    object = %{"answer" => "OTP isolates failure.", "confidence" => 0.95}

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, AIModel.text_response(model, context, JSON.encode!(object), "structured", object)}
    end)

    agent = Agent.instantiate!(id: unique_id("structured-ai"))

    assert {:ok, _next, [%Jido.Agent.Directive.Reply{signal: reply}]} =
             Agent.cmd(agent, Agent.request_signal!(%{input: "Assess OTP"}))

    assert reply.data.output == object
    assert reply.data.status == :completed
  end
end
