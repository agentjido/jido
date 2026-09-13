defmodule JidoTest.Examples.Applications.SubscriptionTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.Examples.Applications.Subscription.{Agent, Plugin, Runtime}

  test "committed desired state rebuilds the runtime projection after restart", %{jido: jido} do
    id = unique_id("subscription")
    {:ok, agent_server} = Jido.start_agent(jido, Agent, id: id)
    runtime = plugin_runtime(agent_server)

    assert {:ok, committed} =
             Agent.change(agent_server, :subscribe, "orders", input: %{config: %{status: "new"}})

    desired = %{"orders" => %{status: "new"}}
    assert committed.state.subscriptions.desired == desired
    eventually(fn -> Runtime.external(runtime) == desired end)

    Process.exit(runtime, :kill)

    restarted =
      eventually(fn ->
        next = plugin_runtime(agent_server)
        if next != runtime, do: next
      end)

    eventually(fn -> Runtime.external(restarted) == desired end)
    assert Process.alive?(agent_server)

    runtime_ref = Process.monitor(restarted)
    owner_ref = Process.monitor(agent_server)
    assert :ok = Jido.stop_agent(jido, agent_server)
    assert_receive {:DOWN, ^owner_ref, :process, ^agent_server, _reason}
    assert_receive {:DOWN, ^runtime_ref, :process, ^restarted, _reason}
    assert Jido.whereis_agent(jido, id) == nil
  end

  defp plugin_runtime(agent_server) do
    case Jido.AgentServer.children(agent_server)[{:plugin, Plugin}] do
      %{pid: pid} when is_pid(pid) -> pid
      _child -> nil
    end
  end
end
