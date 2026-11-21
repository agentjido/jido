Code.require_file("commit_notifier.ex", __DIR__)

defmodule Jido.Examples.Plugins.CommitNotifierTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Plugins.CommitNotifier.Agent
  alias Jido.Examples.Plugins.CommitNotifier.Plugin

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"commit_notifier_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "the hook and custom Directive observe the same completed commit", %{instance: instance} do
    assert {:ok, server} =
             Jido.start_agent(instance, Agent,
               id: "notifier",
               plugin_runtime_options: [{Plugin, observer: self()}]
             )

    assert :ok = AgentServer.await_ready(server)
    signal = Agent.send_notification_signal!(%{message: "ready"})

    assert {:ok, %{status: :committed, agent_revision: 1, turn_id: turn_id}} =
             AgentServer.call(server, signal)

    assert AgentServer.snapshot(server).agent.state == %{
             last_message: "ready",
             notifications: 1
           }

    assert_receive {:commit_hook, ^turn_id, 1, 1}, 1_000
    assert_receive {:notification_dispatched, ^turn_id, 1, 1, "ready"}, 1_000
  end

  test "an invalid custom Directive prevents the commit and callbacks", %{instance: instance} do
    assert {:ok, server} =
             Jido.start_agent(instance, Agent,
               id: "invalid-notifier",
               plugin_runtime_options: [{Plugin, observer: self()}]
             )

    assert :ok = AgentServer.await_ready(server)
    signal = Agent.send_notification_signal!(%{message: ""})

    assert {:ok, %{status: :failed, error: %Jido.Error.ValidationError{}}} =
             AgentServer.call(server, signal)

    assert AgentServer.snapshot(server).agent_revision == 0
    refute_receive {:commit_hook, _, _, _}
    refute_receive {:notification_dispatched, _, _, _, _}
  end
end
