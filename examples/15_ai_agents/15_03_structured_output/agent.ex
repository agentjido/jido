defmodule Jido.Examples.AI.StructuredOutput.Agent do
  @moduledoc "An AI Agent with a strict structured response contract."

  @answer_schema %{
    "type" => "object",
    "properties" => %{
      "answer" => %{"type" => "string"},
      "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1}
    },
    "required" => ["answer", "confidence"],
    "additionalProperties" => false
  }

  use Jido.AI.Agent, name: "structured_output_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Return a concise assessment."

      output_schema(%{
        "type" => "object",
        "properties" => %{
          "answer" => %{"type" => "string"},
          "confidence" => %{"type" => "number", "minimum" => 0, "maximum" => 1}
        },
        "required" => ["answer", "confidence"],
        "additionalProperties" => false
      })
    end
  end

  @doc "Returns the JSON Schema supplied to the model and output validator."
  def answer_schema, do: @answer_schema
end
