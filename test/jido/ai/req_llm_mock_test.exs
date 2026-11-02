defmodule Jido.AI.ReqLLMMockTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Context.Snapshot
  alias Jido.AITest.{ChainOfThoughtAgent, SimpleAgent}
  alias Jido.Agent.Directive.Reply

  setup {Req.Test, :set_req_test_from_context}
  setup {Req.Test, :verify_on_exit!}

  test "ReAct uses the prepared Context through the ReqLLM HTTP mock path" do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      body = request_body(conn)
      send(owner, {:req_llm_request, body})
      json_response(conn, "req-mock-tools", tool_response())
    end)

    Req.Test.expect(__MODULE__, fn conn ->
      body = request_body(conn)
      send(owner, {:req_llm_request, body})
      json_response(conn, "req-mock-answer", text_response("The answer is 5.", 30, 6))
    end)

    agent = SimpleAgent.instantiate!(id: "req-llm-mock-react")
    signal = SimpleAgent.request_signal!(%{input: "Add 2 and 3."} |> with_req_llm_mock())

    assert {:ok, agent, [%Reply{signal: reply}]} = SimpleAgent.cmd(agent, signal)
    assert reply.data.status == :completed
    assert reply.data.output == "The answer is 5."
    assert reply.data.model_calls == 2

    assert_receive {:req_llm_request, first_request}
    assert_receive {:req_llm_request, second_request}

    assert Enum.map(first_request["input"], & &1["role"]) == ["system", "user"]
    assert Enum.any?(first_request["tools"], &(&1["name"] == "add"))

    assert Enum.map(second_request["input"], &{&1["role"], &1["type"]}) == [
             {"system", nil},
             {"user", nil},
             {nil, "function_call"},
             {nil, "function_call_output"}
           ]

    assert [first_attempt, second_attempt] = reply.data.model_attempts
    first_before = Snapshot.decode!(first_attempt.context.before)
    first_after = Snapshot.decode!(first_attempt.context.after)
    second_before = Snapshot.decode!(second_attempt.context.before)

    assert first_before["stage"] == "prepared"
    assert first_after["stage"] == "completed"
    assert first_after["response"]["call_metadata"]["usage"]["input_tokens"] == 20
    assert is_binary(first_after["response"]["call_metadata"]["request_id"])
    assert second_before["shape"]["message_count"] == 4

    assistant =
      agent.state.session.thread.entries
      |> Enum.filter(&(&1.kind == :ai_message))
      |> List.last()

    assert assistant.payload["content"] == "The answer is 5."
  end

  test "Chain of Thought uses the same ReqLLM HTTP mock path" do
    owner = self()

    Req.Test.expect(__MODULE__, fn conn ->
      body = request_body(conn)
      send(owner, {:req_llm_request, body})

      json_response(
        conn,
        "req-mock-cot",
        text_response(
          Jason.encode!(%{
            steps: [
              %{number: 1, content: "Read the value."},
              %{number: 2, content: "Add one."},
              %{number: 3, content: "Check it."}
            ],
            conclusion: "4"
          }),
          18,
          12
        )
      )
    end)

    agent = ChainOfThoughtAgent.instantiate!(id: "req-llm-mock-cot")

    signal =
      ChainOfThoughtAgent.request_signal!(%{input: "What is 3 plus 1?"} |> with_req_llm_mock())

    assert {:ok, _agent, [%Reply{signal: reply}]} = ChainOfThoughtAgent.cmd(agent, signal)
    assert reply.data.status == :completed
    assert reply.data.reasoning.steps_count == 3
    assert reply.data.reasoning.conclusion == "4"

    assert_receive {:req_llm_request, request}
    assert Enum.map(request["input"], & &1["role"]) == ["system", "user"]
    refute Map.has_key?(request, "tools")
    assert request["text"]["format"]["type"] == "json_schema"

    assert [attempt] = reply.data.model_attempts
    after_context = Snapshot.decode!(attempt.context.after)
    assert after_context["response"]["call_metadata"]["usage"]["input_tokens"] == 18
    assert is_binary(after_context["response"]["call_metadata"]["request_id"])
  end

  defp with_req_llm_mock(params) do
    Map.put(params, :options, %{
      api_key: "offline-test-key",
      max_retries: 0,
      max_tokens: 128,
      req_http_options: [plug: {Req.Test, __MODULE__}],
      temperature: 0.0
    })
  end

  defp request_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  defp json_response(conn, request_id, body) do
    conn
    |> Plug.Conn.put_resp_header("x-request-id", request_id)
    |> Req.Test.json(body)
  end

  defp tool_response do
    response(
      "resp-mock-tools",
      [
        %{
          "arguments" => Jason.encode!(%{left: 2, right: 3}),
          "call_id" => "call-add",
          "id" => "fc-mock-add",
          "name" => "add",
          "status" => "completed",
          "type" => "function_call"
        }
      ],
      20,
      4
    )
  end

  defp text_response(text, input_tokens, output_tokens) do
    response(
      "resp-mock-text",
      [
        %{
          "content" => [
            %{
              "annotations" => [],
              "logprobs" => [],
              "text" => text,
              "type" => "output_text"
            }
          ],
          "id" => "msg-mock-text",
          "role" => "assistant",
          "status" => "completed",
          "type" => "message"
        }
      ],
      input_tokens,
      output_tokens
    )
  end

  defp response(id, output, input_tokens, output_tokens) do
    %{
      "created_at" => 1,
      "error" => nil,
      "id" => id,
      "incomplete_details" => nil,
      "model" => "gpt-4o-mini-2024-07-18",
      "object" => "response",
      "output" => output,
      "parallel_tool_calls" => true,
      "status" => "completed",
      "usage" => %{
        "input_tokens" => input_tokens,
        "input_tokens_details" => %{"cached_tokens" => 0},
        "output_tokens" => output_tokens,
        "output_tokens_details" => %{"reasoning_tokens" => 0},
        "total_tokens" => input_tokens + output_tokens
      }
    }
  end
end
