defmodule Jido.Examples.RequestModes do
  @moduledoc """
  Records labels so callers can compare Agent Server request modes.
  """
  use Jido.Agent, name: "runtime_request_modes"

  state do
    schema Jido.Joi.object(%{history: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/request_modes"

    route "examples.runtime.request_modes.record", as: :record do
      action %{label: label},
        schema: Jido.Joi.object(%{label: Jido.Joi.string() |> Jido.Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | history: context.agent_state.history ++ [label]}}
      end
    end
  end
end
