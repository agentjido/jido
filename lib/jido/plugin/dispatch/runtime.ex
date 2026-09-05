defmodule Jido.Plugin.Dispatch.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init), do: {:ok, init}

  @impl true
  def handle_call({:deliver, signal, target}, _from, init) do
    {:reply, Jido.Signal.Dispatch.dispatch(signal, target), init}
  end
end
