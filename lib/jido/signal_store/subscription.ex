defmodule Jido.SignalStore.Subscription do
  @moduledoc false

  use TypedStruct
  alias Jido.SignalStore
  alias Jido.SignalStore.{RecordedEvent, Subscription}

  typedstruct do
    field(:agent, Jido.Agent.t(), enforce: true)
    field(:backoff, any(), enforce: true)
    field(:concurrency, pos_integer(), enforce: true)
    field(:partition_by, (RecordedEvent -> any()) | nil, default: nil)
    field(:subscribe_to, SignalStore.Adapter.stream_uuid() | :all, enforce: true)
    field(:subscribe_from, SignalStore.Adapter.start_from(), enforce: true)
    field(:subscription_name, SignalStore.Adapter.subscription_name(), enforce: true)
    field(:subscription_opts, Keyword.t(), enforce: true)
    field(:subscription_pid, pid() | nil, default: nil)
    field(:subscription_ref, reference() | nil, default: nil)
  end

  def new(opts) do
    %Subscription{
      agent: Keyword.fetch!(opts, :agent),
      backoff: init_backoff(),
      concurrency: parse_concurrency(opts),
      partition_by: parse_partition_by(opts),
      subscription_name: Keyword.fetch!(opts, :subscription_name),
      subscription_opts: Keyword.fetch!(opts, :subscription_opts),
      subscribe_to: parse_subscribe_to(opts),
      subscribe_from: parse_subscribe_from(opts)
    }
  end

  @spec subscribe(Subscription.t(), pid()) :: {:ok, Subscription.t()} | {:error, any()}
  def subscribe(%Subscription{} = subscription, pid) do
    with {:ok, pid} <- subscribe_to(subscription, pid) do
      subscription_ref = Process.monitor(pid)

      subscription = %Subscription{
        subscription
        | subscription_pid: pid,
          subscription_ref: subscription_ref
      }

      {:ok, subscription}
    end
  end

  @spec backoff(Subscription.t()) :: {non_neg_integer(), Subscription.t()}
  def backoff(%Subscription{} = subscription) do
    %Subscription{backoff: backoff} = subscription

    {next, backoff} = :backoff.fail(backoff)

    subscription = %Subscription{subscription | backoff: backoff}

    {next, subscription}
  end

  @spec ack_event(Subscription.t(), RecordedEvent.t()) :: :ok
  def ack_event(%Subscription{} = subscription, %RecordedEvent{} = event) do
    %Subscription{agent: agent, subscription_pid: subscription_pid} = subscription

    SignalStore.ack_event(agent, subscription_pid, event)
  end

  @spec reset(Subscription.t()) :: Subscription.t()
  def reset(%Subscription{} = subscription) do
    %Subscription{
      agent: agent,
      subscribe_to: subscribe_to,
      subscription_name: subscription_name,
      subscription_pid: subscription_pid,
      subscription_ref: subscription_ref
    } = subscription

    Process.demonitor(subscription_ref)

    :ok = SignalStore.unsubscribe(agent, subscription_pid)
    :ok = SignalStore.delete_subscription(agent, subscribe_to, subscription_name)

    %Subscription{
      subscription
      | backoff: init_backoff(),
        subscription_pid: nil,
        subscription_ref: nil
    }
  end

  defp subscribe_to(%Subscription{} = subscription, pid) do
    %Subscription{
      agent: agent,
      concurrency: concurrency,
      partition_by: partition_by,
      subscribe_to: subscribe_to,
      subscription_name: subscription_name,
      subscription_opts: subscription_opts,
      subscribe_from: subscribe_from
    } = subscription

    opts =
      subscription_opts
      |> Keyword.put(:concurrency_limit, concurrency)
      |> Keyword.put(:partition_by, partition_by)

    SignalStore.subscribe_to(
      agent,
      subscribe_to,
      subscription_name,
      pid,
      subscribe_from,
      opts
    )
  end

  defp parse_concurrency(opts) do
    case opts[:concurrency] || 1 do
      concurrency when is_integer(concurrency) and concurrency >= 1 ->
        concurrency

      invalid ->
        raise ArgumentError, message: "invalid `concurrency` option: " <> inspect(invalid)
    end
  end

  defp parse_partition_by(opts) do
    case opts[:partition_by] do
      partition_by when is_function(partition_by, 1) ->
        partition_by

      nil ->
        nil

      invalid ->
        raise ArgumentError, message: "invalid `partition_by` option: " <> inspect(invalid)
    end
  end

  defp parse_subscribe_to(opts) do
    case opts[:subscribe_to] || :all do
      :all ->
        :all

      stream when is_binary(stream) ->
        stream

      invalid ->
        raise ArgumentError, message: "invalid `subscribe_to` option: " <> inspect(invalid)
    end
  end

  defp parse_subscribe_from(opts) do
    case opts[:subscribe_from] || :origin do
      start_from when start_from in [:origin, :current] ->
        start_from

      start_from when is_integer(start_from) ->
        start_from

      invalid ->
        raise ArgumentError, message: "invalid `start_from` option: " <> inspect(invalid)
    end
  end

  @backoff_min :timer.seconds(1)
  @backoff_max :timer.minutes(1)

  # Exponential backoff with jitter
  defp init_backoff do
    :backoff.init(@backoff_min, @backoff_max) |> :backoff.type(:jitter)
  end
end
