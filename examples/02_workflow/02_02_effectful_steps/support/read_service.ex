defmodule Jido.Examples.EffectfulSteps.ReadService do
  @moduledoc "A local service with fixed or ordered responses and a visible call log."
  use Elixir.Agent

  def start_link(responses),
    do: Elixir.Agent.start_link(fn -> %{responses: responses, calls: []} end)

  def call(server, operation, input) do
    Elixir.Agent.get_and_update(server, fn state ->
      {response, responses} =
        case Map.fetch!(state.responses, operation) do
          [response | rest] -> {response, Map.put(state.responses, operation, rest)}
          response -> {response, state.responses}
        end

      {response, %{state | responses: responses, calls: state.calls ++ [{operation, input}]}}
    end)
  end

  def calls(server), do: Elixir.Agent.get(server, & &1.calls)
end
