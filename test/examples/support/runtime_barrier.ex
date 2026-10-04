defmodule JidoTest.Examples.RuntimeBarrier do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def arm(observer), do: GenServer.call(__MODULE__, {:arm, observer})
  def wait, do: GenServer.call(__MODULE__, :wait, 5_000)
  def release, do: GenServer.call(__MODULE__, :release)

  @impl true
  def init(_state), do: {:ok, %{observer: nil, waiter: nil}}

  @impl true
  def handle_call({:arm, observer}, _from, state),
    do: {:reply, :ok, %{state | observer: observer, waiter: nil}}

  def handle_call(:wait, from, %{observer: observer, waiter: nil} = state) do
    send(observer, :runtime_barrier_waiting)
    {:noreply, %{state | waiter: from}}
  end

  def handle_call(:release, _from, %{waiter: waiter} = state) when not is_nil(waiter) do
    GenServer.reply(waiter, :ok)
    {:reply, :ok, %{state | waiter: nil}}
  end
end
