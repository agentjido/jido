defmodule Jido.AI.Reasoning.TreeOfThoughts.Actions.PrepareCall do
  @moduledoc "Prepares one generation, evaluation, or synthesis model call."

  @thoughts_schema %{
    "type" => "object",
    "properties" => %{
      "thoughts" => %{
        "type" => "array",
        "minItems" => 2,
        "items" => %{
          "type" => "object",
          "properties" => %{"content" => %{"type" => "string", "minLength" => 1}},
          "required" => ["content"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["thoughts"],
    "additionalProperties" => false
  }

  @scores_schema %{
    "type" => "object",
    "properties" => %{
      "thoughts" => %{
        "type" => "array",
        "minItems" => 2,
        "items" => %{
          "type" => "object",
          "properties" => %{
            "content" => %{"type" => "string", "minLength" => 1},
            "score" => %{"type" => "number", "minimum" => 0, "maximum" => 1}
          },
          "required" => ["content", "score"],
          "additionalProperties" => false
        }
      }
    },
    "required" => ["thoughts"],
    "additionalProperties" => false
  }

  @answer_schema %{
    "type" => "object",
    "properties" => %{"answer" => %{"type" => "string", "minLength" => 1}},
    "required" => ["answer"],
    "additionalProperties" => false
  }

  use Jido.Action,
    id: "jido.ai/reasoning/tree-of-thoughts/actions/prepare-call",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_prepare_call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: %{turn: turn} = state}, _context) do
    state = Map.put_new(state, :phase, :generate)
    {instruction, output_schema} = request(state)

    turn =
      turn
      |> Map.put(:repair_instruction, instruction)
      |> Map.put(:output_schema, output_schema)

    {:ok,
     %{
       state: Map.put(state, :turn, turn),
       persist_message: state.phase == :synthesize
     }}
  end

  defp request(%{phase: :generate}) do
    {"Generate four distinct candidate approaches to the user's task.", @thoughts_schema}
  end

  defp request(%{phase: :evaluate, thoughts: thoughts}) do
    instruction = "Evaluate each candidate from this JSON list: " <> Jason.encode!(thoughts)
    {instruction, @scores_schema}
  end

  defp request(%{phase: :synthesize, selected: selected}) do
    instruction = "Synthesize the best final answer from this JSON list: " <> Jason.encode!(selected)
    {instruction, @answer_schema}
  end
end
