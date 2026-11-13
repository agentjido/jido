Code.require_file("distribution_boundaries.ex", __DIR__)

defmodule Jido.Examples.Operations.DistributionBoundariesTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.Examples.Operations.{DistributedIdentityAgent, DistributionBoundary}

  test "a Ref survives process shutdown but contains no runtime location" do
    suffix = System.unique_integer([:positive])
    instance = :"distribution_boundary_#{suffix}"
    namespace = "examples/operations/distribution/#{suffix}"
    start_supervised!({Jido, name: instance, namespace: namespace}, id: instance)

    ref = Ref.new!(namespace: namespace, partition: "tenant-7", id: "agent-7")

    assert {:ok, server} =
             Jido.start_agent(instance, DistributedIdentityAgent,
               id: ref.id,
               partition: ref.partition
             )

    assert :ok = Jido.AgentServer.await_ready(server)
    assert {:ok, map} = DistributionBoundary.encode_ref(ref)
    assert {:ok, ^ref} = DistributionBoundary.decode_ref(map)
    refute Map.has_key?(map, "pid")
    refute Map.has_key?(map, "node")
    refute Map.has_key?(map, "module")

    assert :ok = Jido.stop_agent(instance, server)
    assert {:error, _reason} = Jido.status(instance, ref)
    assert {:ok, ^ref} = DistributionBoundary.decode_ref(map)
  end

  test "a namespace is part of identity and does not grant authorization" do
    ref = Ref.new!(namespace: "cluster-a", id: "agent-7")
    other = Ref.new!(namespace: "cluster-b", id: "agent-7")
    refute ref == other
  end
end
