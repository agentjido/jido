defmodule Jido.Bus.Adapters.InMemory.Subscriber do
  @moduledoc false

  alias Jido.Bus.RecordedSignal
  alias __MODULE__

  defstruct [:pid, in_flight_signals: [], pending_signals: []]

  def new(pid), do: %Subscriber{pid: pid}

  def available?(%Subscriber{in_flight_signals: []}), do: true
  def available?(%Subscriber{}), do: false

  def ack(%Subscriber{} = subscriber, ack) do
    %Subscriber{in_flight_signals: in_flight_signals, pending_signals: pending_signals} =
      subscriber

    in_flight_signals =
      Enum.reject(in_flight_signals, fn %RecordedSignal{signal_number: signal_number} ->
        signal_number <= ack
      end)

    subscriber = %Subscriber{subscriber | in_flight_signals: in_flight_signals}

    case pending_signals do
      [pending_signal | pending_signals] ->
        subscriber = %Subscriber{subscriber | pending_signals: pending_signals}

        send_signal(subscriber, pending_signal)

      [] ->
        subscriber
    end
  end

  def publish(%Subscriber{} = subscriber, %RecordedSignal{} = signal) do
    %Subscriber{in_flight_signals: in_flight_signals, pending_signals: pending_signals} =
      subscriber

    if Enum.any?(in_flight_signals) do
      %Subscriber{subscriber | pending_signals: pending_signals ++ [signal]}
    else
      send_signal(subscriber, signal)
    end
  end

  defp send_signal(%Subscriber{} = subscriber, %RecordedSignal{} = signal) do
    %Subscriber{in_flight_signals: in_flight_signals, pid: pid} = subscriber

    send(pid, {:signals, [signal]})

    %Subscriber{subscriber | in_flight_signals: in_flight_signals ++ [signal]}
  end
end
