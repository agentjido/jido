defmodule Jido.Bus.Adapter do
  @moduledoc """
  Defines the behaviour to be implemented by an signal store adapter to be used by Commanded.
  """

  alias Jido.Bus.{Signal, RecordedSignal, Snapshot}

  @type bus :: map
  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()
  @type stream_id :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_id :: String.t()
  @type error :: term

  @doc """
  Return a child spec defining all processes required by the signal store.
  """
  @callback child_spec(application, config) ::
              {:ok, [:supervisor.child_spec() | {module, term} | module], bus}

  @doc """
  Append one or more signals to a stream atomically.
  """
  @callback publish(
              bus,
              stream_id,
              expected_version,
              signals :: list(Signal.t()),
              opts :: Keyword.t()
            ) ::
              :ok
              | {:error, :wrong_expected_version}
              | {:error, error}

  @doc """
  Streams signals from the given stream, in the order in which they were
  originally written.
  """
  @callback replay(
              bus,
              stream_id,
              start_version :: non_neg_integer,
              read_batch_size :: non_neg_integer
            ) ::
              Enumerable.t()
              | {:error, :stream_not_found}
              | {:error, error}

  @doc """
  Create a transient subscription to a single signal stream.

  The signal store will publish any signals appended to the given stream to the
  `subscriber` process as an `{:signals, signals}` message.

  The subscriber does not need to acknowledge receipt of the signals.
  """
  @callback subscribe(bus, stream_id | :all) ::
              :ok | {:error, error}

  @doc """
  Create a persistent subscription to an signal stream.
  """
  @callback subscribe_persistent(
              bus,
              stream_id | :all,
              subscription_name,
              subscriber,
              start_from,
              opts :: Keyword.t()
            ) ::
              {:ok, subscription}
              | {:error, :subscription_already_exists}
              | {:error, error}

  @doc """
  Acknowledge receipt and successful processing of the given signal received from
  a subscription to an signal stream.
  """
  @callback ack(bus, pid, RecordedSignal.t()) :: :ok

  @doc """
  Unsubscribe an existing subscriber from signal notifications.

  This should not delete the subscription.
  """
  @callback unsubscribe(bus, subscription) :: :ok

  @doc """
  Delete an existing subscription.
  """
  @callback unsubscribe(
              bus,
              stream_id | :all,
              subscription_name
            ) ::
              :ok | {:error, :subscription_not_found} | {:error, error}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(bus, source_id) ::
              {:ok, Snapshot.t()} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(bus, Snapshot.t()) ::
              :ok | {:error, error}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(bus, source_id) ::
              :ok | {:error, error}
end
