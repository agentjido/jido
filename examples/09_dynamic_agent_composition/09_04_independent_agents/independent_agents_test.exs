Code.require_file("../support/worker.ex", __DIR__)
Code.require_file("independent_agents.ex", __DIR__)

defmodule Jido.Examples.IndependentAgentsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.IndependentAgents

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"independent_agents_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "stopping one independent Agent does not stop another", %{instance: instance} do
    assert {:ok, first} = IndependentAgents.start(instance, "first")
    assert {:ok, second} = IndependentAgents.start(instance, "second")
    assert :ok = AgentServer.await_ready(first)
    assert :ok = AgentServer.await_ready(second)

    assert {:ok, %{status: :committed}} = IndependentAgents.calculate(first, "a", 2)
    assert :ok = Jido.stop_agent(instance, first)
    refute Process.alive?(first)

    assert {:ok, %{status: :committed}} = IndependentAgents.calculate(second, "b", 3)
    assert AgentServer.snapshot(second).agent.state.completed == [%{request_id: "b", value: 6}]
  end
end
