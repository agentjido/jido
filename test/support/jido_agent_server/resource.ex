defmodule Jido.Test.AgentServer.Resource do
  @moduledoc false
  use GenServer

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init) do
    if observer = init.options[:observer] do
      event = init.options[:resource_event] || :resource
      send(observer, {event, self(), init})
    end

    {:ok, init}
  end

  @impl true
  def handle_call(:owner, _from, init), do: {:reply, init.agent_server, init}
end
