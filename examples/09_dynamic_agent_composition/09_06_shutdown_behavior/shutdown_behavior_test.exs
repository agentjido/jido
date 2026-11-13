Code.require_file("shutdown_behavior.ex", __DIR__)
Code.require_file("../support/worker.ex", __DIR__)

defmodule Jido.Examples.AgentShutdownTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Examples.{AgentShutdown, Worker}

  test "activation and instance shutdown have different durable boundaries" do
    suffix = System.unique_integer([:positive])
    instance = :"shutdown_source_#{suffix}"
    rebound = :"shutdown_rebound_#{suffix}"
    namespace = "examples/shutdown/#{suffix}"
    persistence = {Jido.Persistence.ETS, table: :"shutdown_store_#{suffix}"}

    start_supervised!({Jido, name: instance, namespace: namespace, persistence: persistence}, id: instance)

    first_ref = Ref.new!(namespace: namespace, id: "first")
    second_ref = Ref.new!(namespace: namespace, id: "second")

    for ref <- [first_ref, second_ref] do
      assert {:ok, ^ref} = Jido.create_agent(instance, ref, Worker)
      assert {:ok, server} = Jido.activate_agent(instance, ref)
      assert :ok = AgentServer.await_ready(server)
    end

    {:ok, first_pid} = Jido.resolve_agent(instance, first_ref)
    {:ok, second_pid} = Jido.resolve_agent(instance, second_ref)

    assert {:ok, %{agent: %{id: "first"}}} = AgentShutdown.stop_activation(instance, first_ref)
    refute Process.alive?(first_pid)
    assert Process.alive?(second_pid)

    assert {:ok, first_reactivated} = AgentShutdown.reactivate(instance, first_ref)
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

    for ref <- [first_ref, second_ref] do
      assert {:ok, server} = AgentShutdown.reactivate(rebound, ref)
      assert :ok = AgentServer.await_ready(server)
      assert AgentServer.snapshot(server).agent.id == ref.id
    end
  end
end
