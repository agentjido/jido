defmodule Jido.Examples.TurnControl do
  @moduledoc """
  Provides a small state change for the public Turn control lifecycle.
  """
  use Jido.Agent, name: "runtime_turn_control"

  agent do
    schema Zoi.object(%{completed: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/runtime/turn_control"

    route "examples.runtime.turn_control.complete", as: :complete do
      action %{name: name},
        schema: Zoi.object(%{name: Zoi.string() |> Zoi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | completed: context.agent_state.completed ++ [name]}}
      end
    end
  end
end
