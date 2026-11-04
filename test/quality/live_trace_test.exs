defmodule JidoTest.Quality.LiveTraceTest do
  use ExUnit.Case, async: true

  alias JidoTest.AI.LiveTrace

  test "the live trace allow-list removes prompts, outputs, and credentials" do
    prompt = "private-live-prompt-#{System.unique_integer([:positive])}"
    secret = "test-provider-secret-#{System.unique_integer([:positive])}"

    events = [
      {
        [:req_llm, :request, :stop],
        %{duration: 10, input_tokens: 8, prompt: prompt},
        %{
          request_id: "request-1",
          provider: :openai,
          api_key: secret,
          request_options: %{conversation_id: "conversation-1", prompt: prompt}
        }
      }
    ]

    document =
      LiveTrace.document(events, %{
        status: :completed,
        model_calls: 1,
        reasoning_steps: 3,
        retries: 0,
        output: prompt,
        api_key: secret,
        usage: %{input_tokens: 8, output_tokens: 4}
      })

    encoded = JSON.encode!(document)

    refute encoded =~ prompt
    refute encoded =~ secret
    assert get_in(document, [:result, :usage]) == %{input_tokens: 8, output_tokens: 4}

    assert get_in(document, [:events, Access.at(0), :metadata]) == %{
             conversation_id: "conversation-1",
             provider: "openai",
             request_id: "request-1"
           }
  end
end
