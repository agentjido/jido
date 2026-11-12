defmodule Jido.Test.Examples.AIModel do
  @moduledoc false

  import Mimic

  def expect_text(text, count \\ 1) when is_binary(text) and is_integer(count) do
    expect(ReqLLM, :generate_text, count, fn model, context, _options ->
      {:ok, text_response(model, context, text)}
    end)
  end

  def expect_stream(text) when is_binary(text) do
    expect(ReqLLM, :stream_text, fn model, context, _options ->
      response = text_response(model, context, text, "offline-stream")
      {:ok, ReqLLM.Cache.stream_response(response, ReqLLM.model!(model), context)}
    end)
  end

  def text_response(model, context, text, id \\ "offline-text", object \\ nil) do
    %ReqLLM.Response{
      id: id,
      model: model,
      context: context,
      finish_reason: :stop,
      message: ReqLLM.Context.assistant(text),
      object: object,
      usage: %{input_tokens: 4, output_tokens: 3}
    }
  end

  def tool_response(model, context, calls, id \\ "offline-tools") do
    %ReqLLM.Response{
      id: id,
      model: model,
      context: context,
      finish_reason: :tool_calls,
      message: ReqLLM.Context.assistant("", tool_calls: calls),
      usage: %{input_tokens: 5, output_tokens: 2}
    }
  end

  def receive_stream(signals \\ []) do
    receive do
      {:signal, signal} ->
        next = signals ++ [signal]

        if signal.type == "jido.ai.model.stream.completed",
          do: next,
          else: receive_stream(next)
    after
      1_000 -> raise ExUnit.AssertionError, message: "stream did not publish a completed Signal"
    end
  end
end
