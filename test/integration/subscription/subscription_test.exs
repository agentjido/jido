Code.require_file("example_test.exs", __DIR__)

defmodule JidoTest.Integration.SubscriptionTest do
  use JidoTest.Case, async: false

  @moduletag :integration

  import ExUnit.CaptureLog

  alias Jido.AgentServer, as: Server
  alias Jido.Signal
  alias JidoTest.Integration.Subscription.{Agent, Plugin, Runtime}

  test "committed desired state repairs runtime state after dispatch failure and restart", %{
    jido: jido
  } do
    {:ok, agent_server} = Jido.start_agent(jido, Agent, id: unique_id("subscription"))
    runtime = plugin_runtime(agent_server)

    subscribe =
      Signal.new!(
        "subscription.change",
        %{operation: :subscribe, topic: "orders", config: %{status: "new"}},
        source: "/test/subscription"
      )

    assert {:ok, agent} = Server.call(agent_server, subscribe)
    assert agent.state.subscriptions.desired == %{"orders" => %{status: "new"}}
    eventually(fn -> Runtime.external(runtime) == agent.state.subscriptions.desired end)

    :ok = Runtime.fail_next(runtime)

    failed_dispatch =
      Signal.new!(
        "subscription.change",
        %{operation: :subscribe, topic: "billing", config: %{plan: "pro"}},
        source: "/test/subscription"
      )

    capture_log(fn ->
      assert {:ok, committed} = Server.call(agent_server, failed_dispatch)
      assert Map.has_key?(committed.state.subscriptions.desired, "billing")
      eventually(fn -> Server.status(agent_server).runtime.error_count == 1 end)
    end)

    refute Map.has_key?(Runtime.external(runtime), "billing")
    Process.exit(runtime, :kill)

    restarted =
      eventually(fn ->
        next = plugin_runtime(agent_server)
        if next != runtime, do: next
      end)

    eventually(fn ->
      Runtime.external(restarted) == Server.agent(agent_server).state.subscriptions.desired
    end)

    assert Map.has_key?(Runtime.external(restarted), "orders")
    assert Map.has_key?(Runtime.external(restarted), "billing")
  end

  defp plugin_runtime(agent_server) do
    case Server.children(agent_server)[{:plugin, Plugin}] do
      %{pid: pid} when is_pid(pid) -> pid
      _child -> nil
    end
  end
end
