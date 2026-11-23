defmodule Jido.Examples.DistributedAgents.TurnStartGate do
  @moduledoc false

  def attach(signal_id) do
    :telemetry.attach(__MODULE__, [:jido, :agent_server, :turn, :start], &__MODULE__.hold/4, signal_id)
  end

  def attach_terminal(instance, address, turn_id) do
    :telemetry.attach(
      __MODULE__,
      [:jido, :persistence, :operation, :stop],
      &__MODULE__.hold_terminal/4,
      {instance, address, turn_id}
    )
  end

  def hold(_event, _measurements, %{signal_id: id}, selected_id) when id == selected_id do
    hold()
  end

  def hold(_event, _measurements, _metadata, _selected_id), do: :ok

  def hold_terminal(
        _event,
        _measurements,
        %{operation: :compare_and_swap, status: :ok, agent_id: agent_id},
        {instance, %{id: agent_id} = address, id}
      ) do
    if match?({:ok, %{status: :committed}}, Jido.turn_result(instance, address, id)), do: hold()
  end

  def hold_terminal(_event, _measurements, _metadata, _target), do: :ok

  defp hold do
    Process.register(self(), __MODULE__)

    receive do
      {__MODULE__, :release} -> :ok
    after
      8_000 -> :ok
    end

    Process.unregister(__MODULE__)
  end

  def release(worker) do
    :ok = :telemetry.detach(__MODULE__)
    send(worker, {__MODULE__, :release})
    :ok
  end
end
