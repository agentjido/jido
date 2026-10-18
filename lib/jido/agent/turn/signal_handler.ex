defmodule Jido.Agent.Turn.SignalHandler do
  @moduledoc false
  use Jido.Action,
    name: "agent_signal_handler",
    schema: Zoi.object(%{handler: Zoi.any()})

  @impl Jido.Action
  def run(%{handler: handler}, context) do
    with {:ok, signal} <- output(handler, context.signal) do
      {:ok, context.agent_state, [Jido.Agent.Directive.emit(signal)]}
    end
  end

  defp output(%{kind: :pass_through}, signal), do: {:ok, signal}

  defp output(%{kind: :transform, target: {module, fun, 1}}, signal) do
    case apply(module, fun, [signal]) do
      {:ok, %Jido.Signal{} = output} ->
        {:ok, output}

      {:error, _} = error ->
        error

      _ ->
        Jido.Agent.Error.fail(
          :invalid_result,
          [],
          "Transform must return {:ok, Signal} or {:error, reason}"
        )
    end
  end
end
