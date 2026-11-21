Code.require_file("subscription_plugin.ex", __DIR__)
Code.require_file("subscription.ex", __DIR__)

defmodule Jido.Examples.Applications.SubscriptionTest do
  use Jido.Test.Case, async: true
  @moduletag :integration
  alias Jido.Examples.Applications.Subscription.{Agent, Plugin, Runtime}

  test "committed state and version rebuild resources after replacement", %{jido: jido} do
    id = unique_id("subscription")
    {:ok, agent_server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Agent, id: id)
    runtime = plugin_runtime(agent_server)
    assert Runtime.info(runtime).bootstrap == %{plugin_state: %{desired: %{}}, state_version: 0}

    assert {:ok, route_signal_1} =
             Agent.change_signal(%{
               operation: :subscribe,
               topic: "orders",
               config: %{status: "new"}
             })

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent_server, route_signal_1)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(agent_server).agent
    )

    desired = %{"orders" => %{status: "new"}}
    assert committed.state.subscriptions.desired == desired

    first =
      eventually(fn ->
        info = Runtime.info(runtime)
        info.external == desired && info.state_version == 1 && info.resources["orders"]
      end)

    assert first.generation == 1

    assert {:ok, route_signal_2} =
             Agent.change_signal(%{
               operation: :subscribe,
               topic: "orders",
               config: %{status: "processed"}
             })

    first_pid = first.pid
    first_ref = Process.monitor(first_pid)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(agent_server, route_signal_2)

      assert turn_result.status in [:committed, :waiting]
      _committed = Jido.AgentServer.snapshot(agent_server).agent
    )

    assert_receive {:DOWN, ^first_ref, :process, ^first_pid, :normal}, 1_000

    second = eventually(fn -> Runtime.info(runtime).resources["orders"] end)
    assert second.pid != first.pid
    assert second.generation == 2
    assert {:error, :stale_resource} = Runtime.input(runtime, first, "old")
    assert :ok = Runtime.input(runtime, second, "new")

    eventually(fn ->
      Jido.AgentServer.snapshot(agent_server).agent.state.events == [
        %{topic: "orders", text: "new"}
      ]
    end)

    second_pid = second.pid
    second_ref = Process.monitor(second_pid)
    activation = Jido.Test.AgentServer.ExampleRuntime.activation(agent_server)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^second_ref, :process, ^second_pid, _reason}, 1_000

    restarted =
      eventually(fn ->
        next = Jido.Test.AgentServer.ExampleRuntime.plugin(activation, Plugin)
        next != runtime && next
      end)

    replacement =
      eventually(fn ->
        info = Runtime.info(restarted)

        info.bootstrap == %{
          plugin_state: %{desired: %{"orders" => %{status: "processed"}}},
          state_version: 3
        } && info.resources["orders"]
      end)

    agent_server = Jido.AgentServer.Supervisor.worker(activation)
    assert :ok = Jido.AgentServer.await_ready(agent_server)
    replacement_pid = replacement.pid
    replacement_ref = Process.monitor(replacement_pid)
    owner_ref = Process.monitor(agent_server)
    assert :ok = Jido.stop_agent(jido, agent_server)
    assert_receive {:DOWN, ^owner_ref, :process, ^agent_server, _reason}, 1_000
    assert_receive {:DOWN, ^replacement_ref, :process, ^replacement_pid, _reason}, 1_000
    assert Jido.whereis_agent(jido, id) == nil
  end

  defp plugin_runtime(agent_server) do
    Jido.Test.AgentServer.ExampleRuntime.plugin(Jido.Test.AgentServer.ExampleRuntime.activation(agent_server), Plugin)
  end
end
