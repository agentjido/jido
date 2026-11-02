defmodule Jido.AI.ModelPrimitivesTest do
  use Covenant.Case, component: "jido_ai.model_execution", async: false

  @moduletag obligation: [
               "jido_ai.model_execution.I1",
               "jido_ai.model_execution.I3",
               "jido_ai.model_execution.I4",
               "jido_ai.model_execution.I5",
               "jido_ai.model_execution.I6"
             ]

  import Mimic

  alias Jido.Agent.Directive.Reply
  alias Jido.AI.Actions.Embed
  alias Jido.AI.Context
  alias Jido.AI.Reasoning.Actions.{GuardInput, GuardOutput}
  alias Jido.AITest.SimpleAgent

  setup :set_mimic_global
  setup :verify_on_exit!

  test "ReAct returns a provider-validated structured object" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert %ReqLLM.Output{type: :object} = options[:output]
      assert options[:output_validation] == :strict

      {:ok,
       %ReqLLM.Response{
         id: "structured-response",
         model: model,
         context: context,
         object: %{"answer" => 42},
         finish_reason: :stop,
         usage: %{input_tokens: 8, output_tokens: 3}
       }}
    end)

    agent = SimpleAgent.instantiate!(id: "structured-agent")

    signal =
      SimpleAgent.request_signal!(%{
        input: "Return the answer.",
        output_schema: %{
          "type" => "object",
          "properties" => %{"answer" => %{"type" => "integer"}},
          "required" => ["answer"]
        }
      })

    assert {:ok, agent, [%Reply{signal: reply}]} = SimpleAgent.cmd(agent, signal)
    assert reply.data.output == %{"answer" => 42}

    assistant =
      agent.state.session.thread.entries
      |> Enum.filter(&(&1.kind == :ai_message and &1.payload["role"] == "assistant"))
      |> List.last()

    assert assistant.payload["content"] == Jason.encode!(%{"answer" => 42})
  end

  test "multimodal input reaches ReqLLM as content parts" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      [_system, user] = ReqLLM.Context.to_list(context)
      assert Enum.map(user.content, & &1.type) == [:text, :image_url]

      {:ok,
       %ReqLLM.Response{
         id: "multimodal-response",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant("A red square."),
         finish_reason: :stop,
         usage: %{input_tokens: 12, output_tokens: 4}
       }}
    end)

    input = [
      %{type: :text, text: "Describe this image."},
      %{type: :image_url, url: "https://example.test/image.png"}
    ]

    agent = SimpleAgent.instantiate!(id: "multimodal-agent")
    signal = SimpleAgent.request_signal!(%{input: input})

    assert {:ok, _agent, [%Reply{signal: reply}]} = SimpleAgent.cmd(agent, signal)
    assert reply.data.output == "A red square."
  end

  test "multimodal input validates existing content part structs" do
    part = %ReqLLM.Message.ContentPart{type: :text, text: 123}
    message = %ReqLLM.Message{role: :user, content: [part]}

    assert {:error, _reason} = Context.new(ReqLLM.Context.new([message]))
  end

  test "multimodal support preserves the plain-text input limit" do
    turn = %{input: String.duplicate("x", 2_001)}

    assert {:ok,
            %{
              allowed: false,
              reason_code: :input,
              reason: "input is longer than 2000 characters"
            }} = GuardInput.run(%{turn: turn}, %{})
  end

  test "the output guard applies the size limit to structured objects" do
    turn = %{tool_requirement: :optional, tool_rounds: 0, tools: []}

    outcome = %{
      status: :ok,
      kind: :final_answer,
      finish_reason: :stop,
      text: "short provider text",
      output: %{"answer" => String.duplicate("x", 4_001)}
    }

    assert {:ok, %{allowed: false, reason: "model output is too long"}} =
             GuardOutput.run(%{turn: turn, outcome: outcome}, %{})
  end

  test "one embedding Action accepts one value or a batch" do
    expect(ReqLLM, :embed, 2, fn model, input, options ->
      assert model == "openai:text-embedding-3-small"
      assert options[:return_usage]

      case input do
        "one" ->
          {:ok, %{embedding: [0.1, 0.2], usage: %{input_tokens: 1, total_tokens: 1}}}

        ["one", "two"] ->
          {:ok,
           %{
             embedding: [[0.1, 0.2], [0.3, 0.4]],
             usage: %{input_tokens: 2, total_tokens: 2}
           }}
      end
    end)

    assert {:ok, single} = Jido.Exec.run(Embed, %{input: "one"})
    assert single.embedding == [0.1, 0.2]
    assert single.usage.input_tokens == 1

    assert {:ok, result} = Jido.Exec.run(Embed, %{input: ["one", "two"]})
    assert result.embedding == [[0.1, 0.2], [0.3, 0.4]]
    assert result.usage.input_tokens == 2
  end

  test "the embedding Action returns provider errors" do
    expect(ReqLLM, :embed, fn _model, _input, _options -> {:error, :unavailable} end)

    params = %{model: "openai:text-embedding-3-small", input: "one", options: %{}}

    assert {:error, :unavailable} = Embed.run(params, %{})
  end
end
