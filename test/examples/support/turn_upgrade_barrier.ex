defmodule JidoTest.Examples.TurnUpgradeBarrier do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def arm(observer), do: GenServer.call(__MODULE__, {:arm, observer})
  def wait, do: GenServer.call(__MODULE__, :wait, 5_000)
  def release, do: GenServer.call(__MODULE__, :release)
  def install(release), do: GenServer.call(__MODULE__, {:install, release})
  def current, do: GenServer.call(__MODULE__, :current)

  @impl true
  def init(state), do: {:ok, Map.merge(state, %{current: 1, observer: nil, waiter: nil})}

  @impl true
  def handle_call({:arm, observer}, _from, state),
    do: {:reply, :ok, %{state | observer: observer, waiter: nil}}

  def handle_call(:wait, from, %{observer: observer, waiter: nil} = state) do
    send(observer, :turn_blocked)
    {:noreply, %{state | waiter: from}}
  end

  def handle_call(:release, _from, %{waiter: waiter} = state) when not is_nil(waiter) do
    GenServer.reply(waiter, state.current)
    {:reply, :ok, %{state | waiter: nil}}
  end

  def handle_call({:install, release}, _from, state),
    do: {:reply, :ok, %{state | current: release}}

  def handle_call(:current, _from, state), do: {:reply, state.current, state}
end
