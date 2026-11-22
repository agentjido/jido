defmodule Jido.Examples.RequestModes do
  @moduledoc """
  Records labels so callers can compare Agent Server request modes.
  """

  alias Jido.Joi

  use Jido.Agent, name: "runtime_request_modes"

  state do
    schema Joi.object(%{history: Joi.list(Joi.string()) |> Joi.default([])})
  end

  routes do
    signal_source "/examples/runtime/request_modes"

    route "examples.runtime.request_modes.record", as: :record do
      action %{label: label},
        schema: Joi.object(%{label: Joi.string() |> Joi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | history: context.agent_state.history ++ [label]}}
      end
    end
  end
end
