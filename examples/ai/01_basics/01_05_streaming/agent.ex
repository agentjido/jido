defmodule Jido.Examples.AI.Streaming.Agent do
  @moduledoc "A response that exposes ReqLLM text chunks."

  use Jido.AI.Agent, name: "streaming_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Reply in short chunks."
    end
  end
end
