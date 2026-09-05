defmodule JidoTest.Integration.Inbox.Plugin do
  use Jido.Plugin

  alias Jido.Plugin.Init
  alias JidoTest.Integration.Inbox.Runtime

  def child_spec(%Init{} = init) do
    Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  end
end

defmodule JidoTest.Integration.Inbox.Runtime do
  use GenServer

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Init
  alias Jido.Signal

  def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

  def push(runtime, event), do: GenServer.cast(runtime, {:push, event})

  @impl true
  def init(%Init{} = init), do: {:ok, %{agent_server: init.agent_server}}

  @impl true
  def handle_cast({:push, event}, state) do
    event = Map.put_new(event, :delay_ms, nil)
    signal = Signal.new!("inbox.event", event, source: "/plugin/inbox")
    Server.cast(state.agent_server, signal)
    {:noreply, state}
  end
end

defmodule JidoTest.Integration.Inbox.Ingest do
  use Jido.Action, name: "pressure_inbox_ingest"

  @impl Jido.Action
  def run(%{event_id: event_id} = params, context) do
    if delay = Map.get(params, :delay_ms), do: Process.sleep(delay)

    if event_id in context.agent_state.seen do
      {:ok, context.agent_state}
    else
      {:ok,
       %{
         context.agent_state
         | seen: context.agent_state.seen ++ [event_id],
           accepted: context.agent_state.accepted + 1
       }}
    end
  end
end

defmodule JidoTest.Integration.Inbox.Flow do
  use Jido.Flow, name: "pressure_inbox_flow"

  flow do
    step "ingest",
      action: JidoTest.Integration.Inbox.Ingest,
      params: %{
        event_id: input(:event_id),
        delay_ms: input(:delay_ms)
      }

    output result("ingest")
  end
end

defmodule JidoTest.Integration.Inbox.Agent do
  use Jido.Agent, name: "pressure_inbox_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([])
           })

    plugin JidoTest.Integration.Inbox.Plugin
  end

  routes do
    route "inbox.event", JidoTest.Integration.Inbox.Flow
  end
end
