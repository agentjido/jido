defmodule Jido.Examples.TurnControl do
  @moduledoc """
  Provides a small state change for the public Turn control lifecycle.
  """
  use Jido.Agent, name: "runtime_turn_control"

  state do
    schema Jido.Joi.object(%{completed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/turn_control"

    route "examples.runtime.turn_control.complete", as: :complete do
      action %{name: name},
        schema: Jido.Joi.object(%{name: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | completed: context.agent_state.completed ++ [name]}}
      end
    end
  end
end
