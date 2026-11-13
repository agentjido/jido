Code.require_file("distribution_boundaries.ex", __DIR__)

defmodule Jido.Examples.Operations.DistributionBoundariesTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.Examples.Operations.{DistributedIdentityAgent, DistributionBoundary}

  test "an Address survives process shutdown but contains no runtime location" do
    suffix = System.unique_integer([:positive])
    instance = :"distribution_boundary_#{suffix}"
    namespace = "examples/operations/distribution/#{suffix}"
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    address = Address.new!(namespace: namespace, partition: "tenant-7", id: "agent-7")

    assert {:ok, server} =
             Jido.start_agent(instance, DistributedIdentityAgent,
               id: address.id,
               partition: address.partition
             )

    assert :ok = Jido.AgentServer.await_ready(server)
    assert {:ok, map} = DistributionBoundary.encode_address(address)
    assert {:ok, ^address} = DistributionBoundary.decode_address(map)
    refute Map.has_key?(map, "pid")
    refute Map.has_key?(map, "node")
    refute Map.has_key?(map, "module")

    assert :ok = Jido.stop_agent(instance, server)
    assert {:error, _reason} = Jido.status(instance, address)
    assert {:ok, ^address} = DistributionBoundary.decode_address(map)
  end

  test "a namespace is part of identity and does not grant authorization" do
    address = Address.new!(namespace: "cluster-a", id: "agent-7")
    other = Address.new!(namespace: "cluster-b", id: "agent-7")
    refute address == other
  end
end
