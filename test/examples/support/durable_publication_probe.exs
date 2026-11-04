defmodule JidoTest.Examples.Durable.PublicationProbe do
  @moduledoc false
  use GenServer
  alias Jido.Examples.Durable.ExternalUncertainty.MemoryProvider

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer, name: __MODULE__)
  def release, do: GenServer.call(__MODULE__, :release)

  # The provider accepts before this test-only boundary holds the Action reply.
  def publish(address, id, report) do
    with :ok <- MemoryProvider.publish(address, id, report),
         do: GenServer.call(__MODULE__, :accepted, :infinity)
  end

  def init(observer), do: {:ok, %{observer: observer, held?: false, waiter: nil}}

  def handle_call(:accepted, from, %{held?: false} = state) do
    send(state.observer, {:publication_accepted, elem(from, 0)})
    {:noreply, %{state | held?: true, waiter: from}}
  end

  def handle_call(:accepted, _, state), do: {:reply, :ok, state}

  def handle_call(:release, _, state) do
    if state.waiter, do: GenServer.reply(state.waiter, :ok)
    {:reply, :ok, %{state | waiter: nil}}
  end
end
