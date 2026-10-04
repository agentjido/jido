defmodule Jido.Examples.RequestModes do
  @moduledoc """
  Records labels so callers can compare Agent Server request modes.
  """
  use Jido.Agent, name: "runtime_request_modes"

  agent do
    schema Zoi.object(%{history: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/runtime/request_modes"

    route "examples.runtime.request_modes.record", as: :record do
      action %{label: label},
        schema: Zoi.object(%{label: Zoi.string() |> Zoi.min(1)}),
        context: context do
        {:ok, %{context.agent_state | history: context.agent_state.history ++ [label]}}
      end
    end
  end
end
