defmodule Jido.Plugin.Heartbeat.Runtime do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Init
  alias Jido.Signal

  @default_interval 5_000
  @default_signal_type "jido.agent.heartbeat"
  @default_source "/plugin/heartbeat"

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(%Init{} = init) do
    with {:ok, config} <- validate_options(init.options) do
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

  defp validate_options(opts) when is_list(opts) do
    config = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      signal_type: Keyword.get(opts, :signal_type, @default_signal_type),
      signal_data: Keyword.get(opts, :signal_data, %{}),
      source: Keyword.get(opts, :source, @default_source)
    }

    cond do
      not is_integer(config.interval) or config.interval <= 0 ->
        {:error, {:invalid_heartbeat_interval, config.interval}}

      not is_binary(config.signal_type) or config.signal_type == "" ->
        {:error, {:invalid_heartbeat_signal_type, config.signal_type}}

      not is_map(config.signal_data) or is_struct(config.signal_data) ->
        {:error, {:invalid_heartbeat_signal_data, config.signal_data}}

      not is_binary(config.source) or config.source == "" ->
        {:error, {:invalid_heartbeat_source, config.source}}

      true ->
        {:ok, config}
    end
  end
end
