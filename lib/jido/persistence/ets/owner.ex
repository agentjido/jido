defmodule Jido.Persistence.ETS.Owner do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_info({:"ETS-TRANSFER", _table, _creator, {:jido_persistence_ets, _name}}, state),
    do: {:noreply, state}
end
