defmodule Jido.Bus.Adapters.InMemory.PersistentSubscription do
  @moduledoc false

  alias Jido.Bus.Adapters.InMemory.Subscriber
  alias Jido.Bus.RecordedSignal
  alias __MODULE__

  defstruct [
    :checkpoint,
    :concurrency_limit,
    :name,
    :partition_by,
    :ref,
    :start_from,
    :stream_id,
    subscribers: []
  ]

  @doc """
  Subscribe a new subscriber to the persistent subscription.
  """
  def subscribe(%PersistentSubscription{} = subscription, pid, checkpoint) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    subscribers = subscribers ++ [Subscriber.new(pid)]

    %PersistentSubscription{subscription | subscribers: subscribers, checkpoint: checkpoint}
  end

  def has_subscriber?(%PersistentSubscription{} = subscription, pid) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    Enum.any?(subscribers, fn
      %Subscriber{pid: ^pid} -> true
      %Subscriber{} -> false
    end)
  end

  @doc """
  Publish signal to any available subscriber.
  """
  def publish(%PersistentSubscription{} = subscription, %RecordedSignal{} = signal) do
    %PersistentSubscription{subscribers: subscribers} = subscription
    %RecordedSignal{signal_number: signal_number} = signal

    if subscriber = subscriber(subscription, signal) do
      subscribers =
        Enum.map(subscribers, fn
          ^subscriber -> Subscriber.publish(subscriber, signal)
          %Subscriber{} = subscriber -> subscriber
        end)

      subscription = %PersistentSubscription{
        subscription
        | subscribers: subscribers,
          checkpoint: signal_number
      }

      {:ok, subscription}
    else
      {:error, :no_subscriber_available}
    end
  end

  @doc """
  Acknowledge a successfully received signal.
  """
  def ack(%PersistentSubscription{} = subscription, ack) do
    %PersistentSubscription{subscribers: subscribers} = subscription

    subscriber =
      Enum.find(subscribers, fn %Subscriber{in_flight_signals: in_flight_signals} ->
        Enum.any?(in_flight_signals, fn %RecordedSignal{signal_number: signal_number} ->
          signal_number == ack
        end)
      end)

    if subscriber do
      subscribers =
        Enum.map(subscribers, fn
          ^subscriber -> Subscriber.ack(subscriber, ack)
          subscriber -> subscriber
        end)

      %PersistentSubscription{subscription | subscribers: subscribers}
    else
      {:error, :unexpected_ack}
    end
  end

  @doc """
  Unsubscribe an existing subscriber from the persistent subscription.
  """
  def unsubscribe(%PersistentSubscription{} = subscription, pid) do
    %PersistentSubscription{checkpoint: checkpoint, subscribers: subscribers} = subscription

    subscriber =
      Enum.find(subscribers, fn
        %Subscriber{pid: ^pid} -> true
        %Subscriber{} -> false
      end)

    if subscriber do
      %Subscriber{in_flight_signals: in_flight_signals} = subscriber

      subscribers = List.delete(subscribers, subscriber)

      checkpoint =
        Enum.reduce(in_flight_signals, checkpoint, fn %RecordedSignal{} = signal, checkpoint ->
          %RecordedSignal{signal_number: signal_number} = signal

          min(signal_number - 1, checkpoint)
        end)

      %PersistentSubscription{subscription | checkpoint: checkpoint, subscribers: subscribers}
    else
      subscription
    end
  end

  # Get the subscriber to send the signal to determined by the partition function
  # if provided, otherwise use a round-robin distribution strategy.
  defp subscriber(%PersistentSubscription{} = subscription, %RecordedSignal{} = signal) do
    %PersistentSubscription{partition_by: partition_by, subscribers: subscribers} = subscription

    if is_function(partition_by, 1) do
      # Find subscriber by partition function
      partition_key = partition_by.(signal)

      index = :erlang.phash2(partition_key, length(subscribers))

      Enum.at(subscribers, index)
    else
      # Find first available subscriber
      Enum.find(subscribers, &Subscriber.available?/1)
    end
  end
end
