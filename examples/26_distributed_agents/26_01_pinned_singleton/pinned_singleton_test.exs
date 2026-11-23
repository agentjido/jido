Code.require_file("pinned_singleton.ex", __DIR__)
Code.require_file("../support/counter.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)

defmodule Jido.Examples.DistributedAgents.PinnedSingletonTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.{Status, TurnResult}
  alias Jido.Examples.DistributedAgents.{Counter, PeerHosts, PinnedSingleton, TurnStartGate}

  @instance Jido.Examples.DistributedAgents.PinnedHost
  @sources [Path.expand("pinned_singleton.ex", __DIR__), Path.expand("../support/counter.ex", __DIR__)]

  setup c do
    PeerHosts.load([c.peer_a, c.peer_b], @sources)
    address = Address.new!(namespace: "examples/distribution/ops", id: "coordinator")
    create_counter(c.peer_a, address)
    %{address: address, owner: {c.node_a, @instance}}
  end

  test "both nodes call one dormant Agent while each node can own its own namespace", c do
    other = Address.new!(namespace: "examples/distribution/billing", id: c.address.id)
    create_counter(c.peer_b, other)

    assert {:error, :not_found} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, c.address])

    [one, two] =
      [{c.peer_a, 1}, {c.peer_b, 2}]
      |> Task.async_stream(
        fn {peer, by} ->
          assert {:ok, %TurnResult{status: :committed} = result} =
                   peer_call(peer, PinnedSingleton, :call, [c.owner, c.address, Counter.add(by)])

          result
        end,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert one.agent_activation_id == two.agent_activation_id
    assert Enum.sort([one.agent_revision, two.agent_revision]) == [1, 2]
    assert {:ok, worker} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, c.address])
    assert node(worker) == c.node_a
    assert peer_call(c.peer_a, AgentServer, :snapshot, [worker]).agent.state.count == 3
    assert peer_call(c.peer_b, Jido, :resident_agent_count, [@instance]) == 0

    assert :ok =
             peer_call(c.peer_a, :erpc, :call, [c.node_b, Jido, :cast, [@instance, other, Counter.add(10)], 6_000])

    peer_eventually(
      fn ->
        match?(
          %Status{agent_revision: 1},
          peer_call(c.peer_a, :erpc, :call, [c.node_b, Jido, :status, [@instance, other], 2_000])
        )
      end,
      timeout: 3_000
    )

    assert {:ok, other_worker} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, other])
    assert node(other_worker) == c.node_b
    assert peer_call(c.peer_b, AgentServer, :snapshot, [other_worker]).agent.state.count == 10
    assert peer_call(c.peer_a, AgentServer, :snapshot, [worker]).agent.state.count == 3

    PeerHosts.stop(c.peer_a, @instance)
    PeerHosts.stop(c.peer_b, @instance)
  end

  test "loss of the route leaves the caller without a result and reconnect restores access", c do
    assert {:ok, %TurnResult{status: :committed, agent_activation_id: activation}} =
             peer_call(c.peer_b, PinnedSingleton, :call, [c.owner, c.address, Counter.add(1)])

    # Block automatic reconnection while the link is down.
    cookie = peer_call(c.peer_b, Node, :get_cookie, [])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, :example_disconnected_peer])
    assert true = peer_call(c.peer_b, Node, :disconnect, [c.node_a])

    assert {:error, {:outcome_unknown, :noconnection}} =
             peer_call(c.peer_b, PinnedSingleton, :call, [c.owner, c.address, Counter.add(100)])

    assert nil == peer_call(c.peer_b, Process, :whereis, [@instance])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, cookie])
    assert true = peer_call(c.peer_b, Node, :connect, [c.node_a])

    assert {:ok, %TurnResult{status: :committed, agent_activation_id: ^activation, agent_revision: 2}} =
             peer_call(c.peer_b, PinnedSingleton, :call, [c.owner, c.address, Counter.add(2)])

    assert {:ok, worker} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, c.address])
    assert peer_call(c.peer_a, AgentServer, :snapshot, [worker]).agent.state.count == 3
    PeerHosts.stop(c.peer_a, @instance)
  end

  test "an accepted Turn can commit after the caller loses its reply", c do
    PeerHosts.load([c.peer_a], [Path.expand("../support/turn_start_gate.ex", __DIR__)])
    signal = Counter.add(5)
    assert :ok = peer_call(c.peer_a, TurnStartGate, :attach, [signal.id])

    request =
      Task.async(fn ->
        peer_call(c.peer_b, PinnedSingleton, :call, [c.owner, c.address, signal])
      end)

    worker =
      peer_eventually(
        fn -> peer_call(c.peer_a, Process, :whereis, [TurnStartGate]) end,
        timeout: 4_000
      )

    assert true = peer_call(c.peer_b, Node, :disconnect, [c.node_a])
    assert {:error, {:outcome_unknown, :noconnection}} = Task.await(request, 7_000)
    assert :ok = peer_call(c.peer_a, TurnStartGate, :release, [worker])

    peer_eventually(
      fn ->
        snapshot = peer_call(c.peer_a, AgentServer, :snapshot, [worker])
        snapshot.agent_revision == 1 and snapshot.agent.state.count == 5
      end,
      timeout: 5_000
    )

    assert nil == peer_call(c.peer_b, Process, :whereis, [@instance])
    PeerHosts.stop(c.peer_a, @instance)
  end

  defp create_counter(peer, address) do
    PeerHosts.start(peer,
      name: @instance,
      namespace: address.namespace,
      persistence: {Jido.Persistence.ETS, table: __MODULE__}
    )

    assert {:ok, ^address} = peer_call(peer, Jido, :create_agent, [@instance, address, Counter])
  end
end
