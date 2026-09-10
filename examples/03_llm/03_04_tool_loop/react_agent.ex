defmodule Jido.Examples.ReActAgent do
  @moduledoc """
  Runs one effectful ReAct Flow for each input Signal.

  Model and tool calls occur during the Flow because their results select the
  next step. The Agent Server commits the final conversation only after the
  complete Flow succeeds.
  """

  use Jido.Agent,
    name: "examples_llm_react_agent",
    description: "Runs one bounded model and tool loop"

  agent do
    schema Zoi.object(%{
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             last_answer: Zoi.string() |> Zoi.default(""),
             turns: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/llm/tool_loop"

    route "examples.llm.tool_loop.ask", Jido.Examples.ReActAgent.ReasonFlow do
      defaults %{messages: [], new_turn?: true, max_steps: 8, steps_remaining: 8}
      define :ask, args: [:prompt]
    end
  end
end
