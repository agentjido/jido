defmodule Jido.Bus.Adapters.PubSub do
  @moduledoc """
  A Jido Bus adapter implementation using Phoenix.PubSub for simple pub/sub messaging.

  This adapter provides basic publish/subscribe functionality without persistence or replay capabilities.
  It is suitable for scenarios where you need lightweight message distribution without message history.

  ## Features

  - Simple publish/subscribe messaging using Phoenix.PubSub
  - Support for stream-based subscriptions
  - Auto-cleanup of subscriptions when subscribers terminate
  - No message persistence or replay capabilities

  ## Configuration

  The adapter requires a Phoenix.PubSub server to be started. This is handled automatically
  when starting the adapter through `child_spec/2`.

  ## Usage

  ```elixir
  # Start the bus with the PubSub adapter
  {:ok, children, bus} = Jido.Bus.Adapters.PubSub.child_spec(MyApp, [])
  Supervisor.start_link(children, strategy: :one_for_one)

  # Subscribe to a stream
  :ok = Jido.Bus.subscribe(bus, "my-stream")

  # Publish signals
  :ok = Jido.Bus.publish(bus, "my-stream", :any_version, [signal], [])

  # Receive signals
  receive do
    {:signal, signal} -> handle_signal(signal)
  end
  ```

  ## Limitations

  This adapter does not support:
  - Message persistence
  - Stream replay
  - Persistent subscriptions
  - Snapshots
  - Message acknowledgments
  """

  @behaviour Jido.Bus.Adapter

  alias Phoenix.PubSub
  alias Jido.Bus

  @doc """
  Returns the child specification for starting the PubSub adapter.

  ## Options

    * `:name` - The name to use for the PubSub server. Defaults to the provided context.

  ## Returns

    * `{:ok, children, bus}` - A tuple containing the child specs to start and the configured bus.
  """
  @impl true
  def child_spec(context, opts) do
    name = Keyword.get(opts, :name, context)
    pubsub_name = :"#{name}.PubSub"

    children = [
      {Phoenix.PubSub, name: pubsub_name}
    ]

    bus = %Bus{
      id: Atom.to_string(name),
      adapter: __MODULE__,
      config: [pubsub_name: pubsub_name]
    }

    {:ok, children, bus}
  end

  @doc """
  Publishes signals to a stream.

  The expected_version parameter is ignored as this adapter does not maintain stream versions.
  """
  @impl true
  def publish(bus, stream_id, _expected_version, signals, _opts) do
    pubsub_name = get_pubsub_name(bus)

    Enum.each(signals, fn signal ->
      PubSub.broadcast(pubsub_name, stream_id, {:signal, signal})
    end)

    :ok
  end

  @doc """
  Not implemented - this adapter does not support stream replay.
  """
  @impl true
  def replay(_bus, _stream_id, _start_version, _batch_size) do
    {:error, :not_implemented}
  end

  @doc """
  Subscribes the current process to a stream.
  """
  @impl true
  def subscribe(bus, stream_id) do
    pubsub_name = get_pubsub_name(bus)
    PubSub.subscribe(pubsub_name, stream_id)
  end

  @doc """
  Not implemented - this adapter does not support persistent subscriptions.
  """
  @impl true
  def subscribe_persistent(_bus, _stream_id, _subscription_name, _subscriber, _start_from, _opts) do
    {:error, :not_implemented}
  end

  @doc """
  Not implemented - this adapter does not support message acknowledgments.
  """
  @impl true
  def ack(_bus, _pid, _recorded_signal) do
    {:error, :not_implemented}
  end

  @doc """
  Unsubscribes from a stream or subscription.

  When given a PID, returns :ok since PubSub handles cleanup automatically.
  When given a stream_id, unsubscribes the current process from that stream.
  """
  @impl true
  def unsubscribe(_bus, subscription) when is_pid(subscription) do
    # For PubSub, we can't unsubscribe by PID directly since Phoenix.PubSub requires topics
    # Instead, we'll return ok since PubSub will auto-cleanup when the process dies
    :ok
  end

  @impl true
  def unsubscribe(bus, stream_id) when is_binary(stream_id) do
    pubsub_name = get_pubsub_name(bus)
    PubSub.unsubscribe(pubsub_name, stream_id)
  end

  @doc """
  Not implemented - this adapter does not support snapshots.
  """
  @impl true
  def unsubscribe(_bus, _one, _two) do
    :ok
  end

  @doc """
  Not implemented - this adapter does not support snapshots.
  """
  @impl true
  def read_snapshot(_bus, _source_id) do
    {:error, :not_implemented}
  end

  @doc """
  Not implemented - this adapter does not support snapshots.
  """
  @impl true
  def record_snapshot(_bus, _snapshot) do
    {:error, :not_implemented}
  end

  @doc """
  Not implemented - this adapter does not support snapshots.
  """
  @impl true
  def delete_snapshot(_bus, _source_id) do
    {:error, :not_implemented}
  end

  # Private helpers

  defp get_pubsub_name(bus) do
    Keyword.fetch!(bus.config, :pubsub_name)
  end
end
