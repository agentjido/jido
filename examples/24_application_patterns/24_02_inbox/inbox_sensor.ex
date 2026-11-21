defmodule Jido.Examples.Applications.Inbox.Sensor do
  @moduledoc "Translates external inbox events into normal Agent Signals."
  use GenServer

  alias Jido.AgentServer
  alias Jido.Plugin.SensorManager.Init

  def start_link(%Init{} = init) do
    GenServer.start_link(__MODULE__, init, name: via(init.agent_id, init.tag))
  end

  @doc "Returns the current process for one Agent and sensor tag."
  def whereis(agent_id, tag) do
    case :global.whereis_name(name(agent_id, tag)) do
      pid when is_pid(pid) -> pid
      :undefined -> nil
    end
  end

  @doc "Pushes one external event into the sensor."
  def push(sensor, event), do: GenServer.cast(sensor, {:push, event})

  @impl true
  def init(%Init{} = init), do: {:ok, init}

  @impl true
  def handle_cast({:push, event}, %Init{} = init) do
    signal =
      Jido.Signal.new!("examples.applications.inbox.event", event,
        source: Map.get(init.config, :source, "/examples/applications/inbox/sensor")
      )

    AgentServer.cast(init.agent_server, signal)
    {:noreply, init}
  end

  defp via(agent_id, tag), do: {:global, name(agent_id, tag)}
  defp name(agent_id, tag), do: {__MODULE__, agent_id, tag}
end
