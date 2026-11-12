defmodule Jido.Examples.StableReplacement do
  @moduledoc "Shows that a stable Agent Ref is independent of its resident worker."

  alias Jido.Examples.Worker

  def calculate(instance, ref, request_id, value) do
    with {:ok, signal} <- Worker.calculate_signal(%{request_id: request_id, value: value}) do
      Jido.call(instance, ref, signal)
    end
  end
end
