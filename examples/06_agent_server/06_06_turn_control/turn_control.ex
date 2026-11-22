defmodule Jido.Examples.TurnControl do
  @moduledoc """
  Provides a small state change for the public Turn control lifecycle.
  """

  alias Jido.Joi

  use Jido.Agent, name: "runtime_turn_control"

  state do
    schema Joi.object(%{completed: Joi.list(Joi.string()) |> Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/turn_control"

    route "examples.runtime.turn_control.complete", as: :complete do
      action %{name: name},
        schema: Joi.object(%{name: Joi.string() |> Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | completed: context.agent_state.completed ++ [name]}}
      end
    end
  end
end
