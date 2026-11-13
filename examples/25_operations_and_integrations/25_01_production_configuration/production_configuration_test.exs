Code.require_file("production_configuration.ex", __DIR__)

defmodule Jido.Examples.Operations.ProductionConfigurationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Operations.{ConfiguredRuntime, RuntimeAgent}

  test "a declared instance starts, serves work, and shuts down its Agent tree" do
    assert {:ok, runtime} = ConfiguredRuntime.start_link(max_tasks: 16)

    try do
      assert {:ok, server} = Jido.start_agent(ConfiguredRuntime, RuntimeAgent, id: "runtime-agent")
      assert :ok = AgentServer.await_ready(server)
      monitor = Process.monitor(server)

      assert {:ok, signal} = RuntimeAgent.check_signal(%{})
      assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, signal)
      assert AgentServer.snapshot(server).agent.state.checks == 1

      assert :ok = Jido.stop(ConfiguredRuntime)
      assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 1_000
      refute Process.alive?(runtime)
    after
      Jido.stop(ConfiguredRuntime)
    end
  end
end
