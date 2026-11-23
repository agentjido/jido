defmodule Jido.Examples.DistributedAgents.PersistenceGate do
  @moduledoc false

  def attach(agent_id) do
    :telemetry.attach(__MODULE__, [:jido, :persistence, :operation, :start], &__MODULE__.hold/4, agent_id)
  end

  def hold(_event, _measurements, %{operation: :compare_and_swap, agent_id: agent_id}, agent_id) do
    :ok = :telemetry.detach(__MODULE__)
    Process.register(self(), __MODULE__)

    receive do
      {__MODULE__, :release} -> :ok
    after
      8_000 -> :ok
    end

    Process.unregister(__MODULE__)
  end

  def hold(_event, _measurements, _metadata, _agent_id), do: :ok

  def release(writer) do
    send(writer, {__MODULE__, :release})
    :ok
  end
end
