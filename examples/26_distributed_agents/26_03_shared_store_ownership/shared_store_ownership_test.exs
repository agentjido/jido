Code.require_file("shared_store_ownership.ex", __DIR__)
Code.require_file("../support/counter.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)

defmodule Jido.Examples.DistributedAgents.SharedStoreOwnershipTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.TurnResult
  alias Jido.Examples.DistributedAgents.{Counter, PeerHosts, SharedStoreOwnership}

  @instance Jido.Examples.DistributedAgents.SharedHost
  @table :distributed_agent_example_records
  @sources [Path.expand("shared_store_ownership.ex", __DIR__), Path.expand("../support/counter.ex", __DIR__)]

  test "two hosts can activate one Address against the same storage record", c do
    peers = [c.peer_a, c.peer_b]
    PeerHosts.load(peers, @sources)
    start_store(c)

    address = Address.new!(namespace: "examples/distribution/shared", id: "coordinator")
    opts = [name: @instance, namespace: address.namespace, persistence: {Jido.Persistence.Mnesia, table: @table}]
    Enum.each(peers, &PeerHosts.start(&1, opts))

    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [@instance, address, Counter])

    assert {:ok, first} =
             peer_call(c.peer_b, SharedStoreOwnership, :activate, [{c.node_a, @instance}, address])

    assert {:ok, %TurnResult{status: :committed}} =
             peer_call(c.peer_a, Jido, :call, [@instance, address, Counter.add(1)])

    assert {:error, :not_found} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])

    assert {:ok, second} =
             peer_call(c.peer_a, SharedStoreOwnership, :activate, [{c.node_b, @instance}, address])

    assert :ok = peer_call(c.peer_b, AgentServer, :await_ready, [second])
    assert node(first) == c.node_a
    assert node(second) == c.node_b
    assert {:ok, ^first} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, address])
    assert {:ok, ^second} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])
    assert peer_call(c.peer_b, AgentServer, :snapshot, [second]).agent.state.count == 1

    Enum.each(peers, fn peer ->
      PeerHosts.stop(peer, @instance)
      assert :stopped = peer_call(peer, :mnesia, :stop, [])
    end)
  end

  defp start_store(c) do
    peers = [c.peer_a, c.peer_b]
    nodes = [c.node_a, c.node_b]

    Enum.each(Enum.zip(peers, ["a", "b"]), fn {peer, label} ->
      dir = Path.join(c.tmp_dir, label)
      File.mkdir_p!(dir)
      assert :stopped = peer_call(peer, :mnesia, :stop, [])
      assert :ok = peer_call(peer, Application, :put_env, [:mnesia, :dir, String.to_charlist(dir)])
    end)

    assert :ok = peer_call(c.peer_a, :mnesia, :create_schema, [nodes])

    Enum.each(peers, fn peer ->
      assert {:ok, _apps} = peer_call(peer, Application, :ensure_all_started, [:mnesia])
      assert :ok = peer_call(peer, :mnesia, :wait_for_tables, [[:schema], 5_000])
    end)

    assert {:atomic, :ok} =
             peer_call(c.peer_a, :mnesia, :create_table, [@table, [attributes: [:key, :value], ram_copies: nodes]])

    Enum.each(peers, fn peer ->
      assert :ok = peer_call(peer, :mnesia, :wait_for_tables, [[@table], 5_000])
    end)
  end
end
