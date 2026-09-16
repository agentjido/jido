defmodule Jido.Examples.Applications.Inbox.Plugin do
  @moduledoc "Owns a small input runtime that translates external events into Signals."
  use Jido.Plugin, agent_server: __MODULE__.Server
end

defmodule Jido.Examples.Applications.Inbox.Plugin.Server do
  use Jido.AgentServer.Plugin

  alias Jido.Plugin.Init
  alias Jido.Examples.Applications.Inbox.Runtime

  def child_spec(%Init{} = init),
    do: Supervisor.child_spec({Runtime, init}, id: Jido.Examples.Applications.Inbox.Plugin)
end

defmodule Jido.Examples.Applications.Inbox.Runtime do
  @moduledoc "Pushes external events into the owning Agent through its public Signal mailbox."
  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Init

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)
  def push(runtime, event), do: GenServer.cast(runtime, {:push, event})

  @impl true
  def init(%Init{} = init), do: {:ok, %{agent_server: init.agent_server}}

  @impl true
  def handle_cast({:push, event}, state) do
    signal =
      Jido.Signal.new!("examples.applications.inbox.event", event,
        source: "/examples/applications/inbox/runtime"
      )

    Server.cast(state.agent_server, signal)
    {:noreply, state}
  end
end
