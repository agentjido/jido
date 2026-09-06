defmodule JidoTest.Examples.Applications.InboxTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Applications.Inbox.{Agent, Plugin, Runtime}

  test "an input Plugin survives bursts, duplicates, and an internal runtime restart", %{
    jido: jido
  } do
    {:ok, agent_server} = Jido.start_agent(jido, Agent, id: unique_id("inbox"))

    runtime =
      eventually(fn ->
        case Server.children(agent_server)[{:plugin, Plugin}] do
          %{pid: pid} when is_pid(pid) -> pid
          _child -> nil
        end
      end)

    Runtime.push(runtime, %{event_id: "slow", delay_ms: 30})
    Runtime.push(runtime, %{event_id: "duplicate"})
    Runtime.push(runtime, %{event_id: "duplicate"})

    Enum.each(1..10, fn index ->
      Runtime.push(runtime, %{event_id: "burst-#{index}"})
    end)

    eventually(fn -> Server.agent(agent_server).state.accepted == 12 end, timeout: 3_000)
    assert Enum.count(Server.agent(agent_server).state.seen, &(&1 == "duplicate")) == 1

    Process.exit(runtime, :kill)

    restarted =
      eventually(fn ->
        case Server.children(agent_server)[{:plugin, Plugin}] do
          %{pid: pid} when is_pid(pid) and pid != runtime -> pid
          _child -> nil
        end
      end)

    assert Process.alive?(agent_server)
    Runtime.push(restarted, %{event_id: "after-restart"})
    eventually(fn -> Server.agent(agent_server).state.accepted == 13 end, timeout: 3_000)
  end
end
