Code.require_file("ownership_ledger.ex", __DIR__)
Code.require_file("../support/worker.ex", __DIR__)

defmodule Jido.Examples.OwnershipTransferTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  import Jido.Test.Eventually

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.Examples.{OwnershipTransfer, Worker}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"ownership_ledger_#{suffix}"
    namespace = "examples/ownership-ledger/#{suffix}"
    store = {Jido.Persistence.ETS, table: :"ownership_ledger_store_#{suffix}"}
    start_supervised!({Jido, name: instance, namespace: namespace, persistence: store}, id: instance)

    agents =
      Map.new(["team-a", "team-b", "worker"], fn id ->
        address = Address.new!(namespace: namespace, id: id)
        assert {:ok, ^address} = Jido.create_agent(instance, address, Worker)
        assert {:ok, server} = Jido.activate_agent(instance, address)
        assert :ok = AgentServer.await_ready(server)
        {id, %{address: address, server: server}}
      end)

    %{instance: instance, agents: agents}
  end

  test "a fenced transfer changes the owner without replacing the worker", c do
    worker = c.agents["worker"]
    team_a = c.agents["team-a"]
    team_b = c.agents["team-b"]

    assert {:ok, adopted} =
             OwnershipTransfer.adopt(c.instance, worker.address, team_a.address, "example-adopt")

    assert {:ok, transferred} =
             OwnershipTransfer.transfer(
               c.instance,
               worker.address,
               team_b.address,
               adopted,
               "example-transfer"
             )

    assert transferred.owner_address == team_b.address
    refute transferred.fence == adopted.fence
    assert {:ok, same_worker} = Jido.resolve_agent(c.instance, worker.address)
    assert same_worker == worker.server
    assert {:ok, ^transferred} = Jido.agent_ownership(c.instance, worker.address)

    assert {:ok, ^transferred} =
             OwnershipTransfer.transfer(
               c.instance,
               worker.address,
               team_b.address,
               adopted,
               "example-transfer"
             )

    assert {:error, :stale_ownership} =
             OwnershipTransfer.transfer(
               c.instance,
               worker.address,
               team_a.address,
               adopted,
               "example-stale-transfer"
             )
  end

  test "only the current owner activation controls shutdown", c do
    worker = c.agents["worker"]
    team_a = c.agents["team-a"]
    team_b = c.agents["team-b"]

    assert {:ok, adopted} =
             OwnershipTransfer.adopt(c.instance, worker.address, team_a.address, "shutdown-adopt")

    assert {:ok, _transferred} =
             OwnershipTransfer.transfer(
               c.instance,
               worker.address,
               team_b.address,
               adopted,
               "shutdown-transfer"
             )

    assert :ok = Jido.stop_agent(c.instance, team_a.server)
    assert {:ok, same_worker} = Jido.resolve_agent(c.instance, worker.address)
    assert same_worker == worker.server

    worker_monitor = Process.monitor(worker.server)
    assert :ok = Jido.stop_agent(c.instance, team_b.server)
    assert_receive {:DOWN, ^worker_monitor, :process, _pid, _reason}, 1_000
    assert_eventually(Jido.resolve_agent(c.instance, worker.address) == {:error, :not_found})

    assert {:ok, replacement} = Jido.activate_agent(c.instance, worker.address)
    refute replacement == worker.server
    assert {:ok, nil} = Jido.agent_ownership(c.instance, worker.address)
  end
end
