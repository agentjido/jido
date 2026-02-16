defmodule JidoTest.SignalCollector do
  @moduledoc false
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, [], opts)
  end

  def get_signals(pid), do: GenServer.call(pid, :get_signals)
  def clear(pid), do: GenServer.call(pid, :clear)

  @impl true
  def init(_opts), do: {:ok, []}

  @impl true
  def handle_info({:signal, signal}, signals), do: {:noreply, [signal | signals]}

  @impl true
  def handle_call(:get_signals, _from, signals), do: {:reply, Enum.reverse(signals), signals}
  def handle_call(:clear, _from, _signals), do: {:reply, :ok, []}
end
