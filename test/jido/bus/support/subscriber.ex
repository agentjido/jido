defmodule Jido.Bus.Subscriber do
  use GenServer

  alias Jido.Bus.Subscriber

  defmodule State do
    defstruct [
      :subscription_opts,
      :signal_store,
      :signal_store_meta,
      :owner,
      :subscription,
      received_signals: [],
      subscribed?: false
    ]
  end

  alias Subscriber.State

  def start_link(signal_store, signal_store_meta, owner, subscription_opts \\ []) do
    state = %State{
      signal_store: signal_store,
      signal_store_meta: signal_store_meta,
      owner: owner,
      subscription_opts: subscription_opts
    }

    GenServer.start_link(__MODULE__, state)
  end

  def init(%State{} = state) do
    %State{
      signal_store: signal_store,
      signal_store_meta: signal_store_meta,
      owner: owner,
      subscription_opts: opts
    } = state

    case signal_store.subscribe_persistent(
           signal_store_meta,
           :all,
           "subscriber",
           self(),
           :origin,
           opts
         ) do
      {:ok, subscription} ->
        state = %State{state | subscription: subscription}

        {:ok, state}

      {:error, error} ->
        send(owner, {:subscribe_error, error, self()})

        {:ok, state}
    end
  end

  def ack(subscriber, signals),
    do: GenServer.call(subscriber, {:ack, signals})

  def subscribed?(subscriber),
    do: GenServer.call(subscriber, :subscribed?)

  def received_signals(subscriber),
    do: GenServer.call(subscriber, :received_signals)

  def handle_call({:ack, signals}, _from, %State{} = state) do
    %State{
      signal_store: signal_store,
      signal_store_meta: signal_store_meta,
      subscription: subscription
    } = state

    :ok = signal_store.ack(signal_store_meta, subscription, List.last(signals))

    {:reply, :ok, state}
  end

  def handle_call(:subscribed?, _from, %State{} = state) do
    %State{subscribed?: subscribed?} = state

    {:reply, subscribed?, state}
  end

  def handle_call(:received_signals, _from, %State{} = state) do
    %State{received_signals: received_signals} = state

    {:reply, received_signals, state}
  end

  def handle_info({:subscribed, subscription}, %State{subscription: subscription} = state) do
    %State{owner: owner} = state

    send(owner, {:subscribed, self(), subscription})

    {:noreply, %State{state | subscribed?: true}}
  end

  def handle_info({:signals, signals}, %State{} = state) do
    %State{owner: owner, received_signals: received_signals} = state

    send(owner, {:signals, self(), signals})

    state = %State{state | received_signals: received_signals ++ signals}

    {:noreply, state}
  end
end
