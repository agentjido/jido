defmodule Jido.AI.Reasoning.TRM.Actions.PrepareCall do
  @moduledoc "Prepares one draft, critique, or revision model call."

  @draft_schema %{
    "type" => "object",
    "properties" => %{"draft" => %{"type" => "string", "minLength" => 1}},
    "required" => ["draft"],
    "additionalProperties" => false
  }

  @critique_schema %{
    "type" => "object",
    "properties" => %{"critique" => %{"type" => "string", "minLength" => 1}},
    "required" => ["critique"],
    "additionalProperties" => false
  }

  @answer_schema %{
    "type" => "object",
    "properties" => %{"answer" => %{"type" => "string", "minLength" => 1}},
    "required" => ["answer"],
    "additionalProperties" => false
  }

  use Jido.Action,
    id: "jido.ai/reasoning/trm/actions/prepare-call",
    vsn: 1,
    name: "jido_ai_trm_prepare_call",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{state: %{turn: turn} = state}, _context) do
    state = Map.put_new(state, :phase, :draft)
    {instruction, output_schema} = request(state)

    turn =
      turn
      |> Map.put(:repair_instruction, instruction)
      |> Map.put(:output_schema, output_schema)

    {:ok,
     %{
       state: Map.put(state, :turn, turn),
       persist_message: state.phase == :revise
     }}
  end

  defp request(%{phase: :draft}) do
    {"Create a strong initial draft answer for the user's task.", @draft_schema}
  end

  defp request(%{phase: :critique, draft: draft}) do
    {"Find the important errors or omissions in this draft: " <> Jason.encode!(draft), @critique_schema}
  end

  defp request(%{phase: :revise, draft: draft, critique: critique}) do
    input = Jason.encode!(%{draft: draft, critique: critique})
    {"Revise the draft with this critique and return the final answer: " <> input, @answer_schema}
  end
end
