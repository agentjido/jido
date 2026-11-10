defmodule Jido.Plugin.Heartbeat.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Heartbeat.Signal.Tick
  alias Jido.Plugin.Init
  alias Jido.Signal

  def start_link({%Init{} = init, config}) when is_map(config),
    do: GenServer.start_link(__MODULE__, {init, config})

  @impl true
  def init({%Init{} = init, config}) do
    state = Map.put(config, :agent_server, init.agent_server)
    {:ok, schedule(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    signal =
      if state.signal_type == Tick.type() do
        Tick.new!(state.signal_data, source: state.source)
      else
        Signal.new!(state.signal_type, state.signal_data, source: state.source)
      end

    Server.cast(state.agent_server, signal)
    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    Process.send_after(self(), :tick, state.interval)
    state
  end
end
