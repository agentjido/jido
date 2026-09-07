defmodule Jido.Plugin.Heartbeat.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Heartbeat
  alias Jido.Plugin.Init
  alias Jido.Signal

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init) do
    with {:ok, config} <- Heartbeat.configuration(init.options) do
      state = Map.put(config, :agent_server, init.agent_server)
      {:ok, schedule(state)}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    signal =
      Signal.new!(state.signal_type, state.signal_data, source: state.source)

    Server.cast(state.agent_server, signal)
    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval)
    state
  end
end
