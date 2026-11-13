Code.require_file("runtime_resource.ex", __DIR__)

defmodule Jido.Examples.Plugins.RuntimeResourceTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Plugins.RuntimeResource.Agent
  alias Jido.Examples.Plugins.RuntimeResource.Plugin

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"runtime_resource_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "the Plugin runtime starts before work and stops with its Agent", %{instance: instance} do
    assert {:ok, server} =
             Jido.start_agent(instance, Agent,
               id: "resource-owner",
               plugin_runtime_options: [{Plugin, observer: self()}]
             )

    assert :ok = AgentServer.await_ready(server)

    assert {:ok, %{status: :committed, agent_revision: 1}} =
             AgentServer.call(server, Agent.inspect_runtime_signal!(%{label: "first"}))

    assert_receive {:runtime_report, "first", 1, report}, 1_000
    assert report.agent_id == "resource-owner"
    assert report.started_at_revision == 0
    assert Process.alive?(report.runtime)
    assert Process.alive?(report.resource)
    assert AgentServer.snapshot(server).agent.state.requests == 1

    runtime_monitor = Process.monitor(report.runtime)
    resource_monitor = Process.monitor(report.resource)
    server_monitor = Process.monitor(server)

    assert :ok = Jido.stop_agent(instance, server)
    assert_receive {:DOWN, ^server_monitor, :process, ^server, _reason}, 1_000
    assert_receive {:DOWN, ^runtime_monitor, :process, _, _reason}, 1_000
    assert_receive {:DOWN, ^resource_monitor, :process, _, _reason}, 1_000
  end
end
