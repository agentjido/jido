defmodule Jido.Examples.DistributedAgents.TurnStartGate do
  @moduledoc false

  def attach(signal_id) do
    :telemetry.attach(__MODULE__, [:jido, :agent_server, :turn, :start], &__MODULE__.hold/4, signal_id)
  end

  def hold(_event, _measurements, %{signal_id: id}, selected_id) when id == selected_id do
    Process.register(self(), __MODULE__)

    receive do
      {__MODULE__, :release} -> :ok
    after
      8_000 -> :ok
    end

    Process.unregister(__MODULE__)
  end

  def hold(_event, _measurements, _metadata, _selected_id), do: :ok

  def release(worker) do
    :ok = :telemetry.detach(__MODULE__)
    send(worker, {__MODULE__, :release})
    :ok
  end
end
