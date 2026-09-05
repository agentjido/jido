defmodule JidoTest.AgentCaseContractTest do
  use JidoTest.Case, async: true

  @moduletag :basic_contract

  alias Jido.AgentServer, as: Server
  alias JidoTest.AgentFixtures.CounterAgent

  defmodule CommitAfterRead do
    @moduledoc false

    use GenServer

    alias Jido.AgentServer, as: Server

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl true
    def init(opts), do: {:ok, Map.new(opts)}

    @impl true
    def handle_call(request, _from, state) when request in [:agent, :snapshot] do
      # Capture one public read, then finish a real turn before returning it.
      # This permits either read API and forces a commit between separate reads.
      result =
        case request do
          :agent -> Server.agent(state.server)
          :snapshot -> Server.snapshot(state.server)
        end

      {:ok, _agent} = Server.call(state.server, state.command)
      {:reply, result, state}
    end

    def handle_call(:status, _from, state) do
      {:reply, Server.status(state.server), state}
    end
  end

  setup %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, CounterAgent, id: unique_id())
    command = signal("counter.add", %{by: 1, label: "between reads"})
    proxy = start_supervised!({CommitAfterRead, server: server, command: command})

    %{server: server, proxy: proxy}
  end

  test "agent_result returns state and version from the same commit", %{
    server: server,
    proxy: proxy
  } do
    result = JidoTest.AgentCase.agent_result(proxy)

    assert %{agent: %{state: %{count: 1}}, state_version: 1} = Server.snapshot(server)
    assert result.state == result.agent.state
    assert result.state.count == result.state_version
  end

  test "an atomic snapshot remains consistent when a turn finishes after the read", %{
    server: server,
    proxy: proxy
  } do
    assert %{agent: %{state: %{count: 0}}, state_version: 0} = Server.snapshot(proxy)
    assert %{agent: %{state: %{count: 1}}, state_version: 1} = Server.snapshot(server)
  end
end
