Code.require_file("shutdown_behavior.ex", __DIR__)
Code.require_file("../support/worker.ex", __DIR__)

defmodule Jido.Examples.AgentShutdownTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.Examples.{AgentShutdown, Worker}

  test "activation and instance shutdown have different durable boundaries" do
    suffix = System.unique_integer([:positive])
    instance = :"shutdown_source_#{suffix}"
    rebound = :"shutdown_rebound_#{suffix}"
    namespace = "examples/shutdown/#{suffix}"
    persistence = {Jido.Persistence.ETS, table: :"shutdown_store_#{suffix}"}

    start_supervised!({Jido, name: instance, namespace: namespace, persistence: persistence}, id: instance)

    first_address = Address.new!(namespace: namespace, id: "first")
    second_address = Address.new!(namespace: namespace, id: "second")

    for address <- [first_address, second_address] do
      assert {:ok, ^address} = Jido.create_agent(instance, address, Worker)
      assert {:ok, server} = Jido.activate_agent(instance, address)
      assert :ok = AgentServer.await_ready(server)
    end

    {:ok, first_pid} = Jido.resolve_agent(instance, first_address)
    {:ok, second_pid} = Jido.resolve_agent(instance, second_address)

    assert {:ok, %{agent: %{id: "first"}}} = AgentShutdown.stop_activation(instance, first_address)
    refute Process.alive?(first_pid)
    assert Process.alive?(second_pid)

    assert {:ok, first_reactivated} = AgentShutdown.reactivate(instance, first_address)
    refute first_reactivated == first_pid

    first_monitor = Process.monitor(first_reactivated)
    second_monitor = Process.monitor(second_pid)
    assert :ok = stop_supervised(instance)
    assert_receive {:DOWN, ^first_monitor, :process, ^first_reactivated, _reason}, 1_000
    assert_receive {:DOWN, ^second_monitor, :process, ^second_pid, _reason}, 1_000

    start_supervised!(
      {Jido, name: rebound, namespace: namespace, persistence: persistence},
      id: rebound
    )

    for address <- [first_address, second_address] do
      assert {:ok, server} = AgentShutdown.reactivate(rebound, address)
      assert :ok = AgentServer.await_ready(server)
      assert AgentServer.snapshot(server).agent.id == address.id
    end
  end
end
