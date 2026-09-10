defmodule Jido.Examples.ReActAgent.Contracts do
  @moduledoc false

  @spec turn_input() :: Zoi.schema()
  def turn_input do
    Zoi.object(%{
      prompt: Zoi.union([Zoi.string(), Zoi.literal(nil)]),
      messages: Zoi.list(Zoi.map()),
      new_turn?: Zoi.boolean(),
      max_steps: Zoi.integer() |> Zoi.min(1),
      steps_remaining: Zoi.integer() |> Zoi.min(0)
    })
  end

  @spec tool_decision() :: Zoi.schema()
  def tool_decision do
    Zoi.object(%{
      kind: Zoi.literal(:tool),
      tool_name: Zoi.string() |> Zoi.min(1),
      tool_input: Zoi.any(),
      messages: Zoi.list(Zoi.map()),
      max_steps: Zoi.integer() |> Zoi.min(1),
      steps_remaining: Zoi.integer() |> Zoi.min(0)
    })
  end

  @spec answer_decision() :: Zoi.schema()
  def answer_decision do
    Zoi.object(%{
      kind: Zoi.literal(:answer),
      answer: Zoi.string() |> Zoi.min(1),
      messages: Zoi.list(Zoi.map()),
      max_steps: Zoi.integer() |> Zoi.min(1),
      steps_remaining: Zoi.integer() |> Zoi.min(0)
    })
  end

  @spec decision() :: Zoi.schema()
  def decision, do: Zoi.union([tool_decision(), answer_decision()])
end
