defmodule Jido.Agent.InstanceManager.Cleanup do
  @moduledoc false
  use GenServer

  @doc false
  def start_link(name) do
    GenServer.start_link(__MODULE__, name)
  end

  @impl true
  def init(name) do
    Process.flag(:trap_exit, true)
    {:ok, name}
  end

  @impl true
  def terminate(_reason, name) do
    :persistent_term.erase({Jido.Agent.InstanceManager, name})
    :ok
  end
end
