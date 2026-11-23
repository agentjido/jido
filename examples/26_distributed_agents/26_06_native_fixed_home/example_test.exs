Code.require_file("example.ex", __DIR__)
Code.require_file("../support/counter.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)
Code.require_file("../support/turn_start_gate.ex", __DIR__)

defmodule Jido.Examples.DistributedAgents.FixedHomeTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.{Status, TurnResult}
  alias Jido.Examples.DistributedAgents.{Counter, FixedHome, PeerHosts, TurnStartGate}

  @sources [
    Path.expand("example.ex", __DIR__),
    Path.expand("../support/counter.ex", __DIR__),
    Path.expand("../support/turn_start_gate.ex", __DIR__)
  ]

  setup c do
    PeerHosts.load([c.peer_a, c.peer_b], @sources)
    namespace = "examples/distribution/native-fixed"
    address = Address.new!(namespace: namespace, id: "counter")
    profile = {Jido.Persistence.ETS, table: __MODULE__}
    opts = FixedHome.options(c.node_a, profile)

    # Ingress starts first. It does not need a home or a usable local Store.
    start(c.peer_b, Keyword.put(opts, :persistence, :adapter_not_installed_on_ingress))
    assert {:error, :cluster_unavailable} = peer_call(c.peer_b, Jido, :call, [FixedHome, address, Counter.add(10)])

    assert {:error, %Jido.Error.ValidationError{}} =
             peer_call(c.peer_b, Jido, :call, [FixedHome, address, Counter.add(10), [turn_id: 42]])

    assert :ok =
             peer_call(c.peer_a, Jido, :change_cluster_home, [profile, namespace, :not_found, {c.node_a, "first-home"}])

    start(c.peer_a, opts)
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [FixedHome, address, Counter])
    %{address: address}
  end

  test "both peers activate one counter and ingress rejects local lifecycles", c do
    local = Address.new!(namespace: "examples/distribution/other", id: c.address.id)

    PeerHosts.start(c.peer_b,
      name: __MODULE__,
      namespace: local.namespace,
      persistence: {Jido.Persistence.ETS, table: __MODULE__}
    )

    assert {:ok, ^local} = peer_call(c.peer_b, Jido, :create_agent, [__MODULE__, local, Counter])
    agent = Counter.instantiate!(id: c.address.id)

    requests = [
      fn -> peer_call(c.peer_a, Jido, :call, [FixedHome, c.address, Counter.add(1)]) end,
      fn -> peer_call(c.peer_b, Jido, :call, [FixedHome, c.address, Counter.add(2), :infinity]) end,
      fn -> peer_call(c.peer_b, Jido, :activate_agent, [FixedHome, c.address]) end,
      fn ->
        peer_call(c.peer_b, Supervisor, :start_child, [Jido.Supervisor, {AgentServer, agent: agent, jido: FixedHome}])
      end
    ]

    [one, two, activation, external] =
      requests |> Task.async_stream(fn request -> request.() end) |> Enum.map(fn {:ok, result} -> result end)

    assert {:ok, %TurnResult{status: :committed} = first} = one
    assert {:ok, %TurnResult{status: :committed} = second} = two
    assert first.agent_activation_id == second.agent_activation_id
    assert Enum.sort([first.agent_revision, second.agent_revision]) == [1, 2]
    assert activation == {:error, :cluster_not_home}
    assert inspect(external) =~ "cluster_not_home"
    assert {:error, :cluster_not_home} = peer_call(c.peer_b, Jido, :start_agent, [FixedHome, agent])
    assert {:error, :not_found} = peer_call(c.peer_b, Jido, :resolve_agent, [FixedHome, c.address])
    assert 0 == peer_call(c.peer_b, Jido, :resident_agent_count, [FixedHome])
    assert %Status{agent_revision: 0} = peer_call(c.peer_b, Jido, :status, [__MODULE__, local])

    other_agent = Counter.instantiate!(id: "unmanaged")

    externally_supervised =
      peer_call(c.peer_a, Supervisor, :start_child, [
        Jido.Supervisor,
        {AgentServer, agent: other_agent, jido: FixedHome}
      ])

    assert inspect(externally_supervised) =~ "cluster_requires_managed_activation"

    assert {:error, :cluster_nonportable_request} =
             peer_call(c.peer_b, Jido, :call, [
               FixedHome,
               c.address,
               Counter.add(4),
               [context: %{caller: self()}]
             ])

    assert {:error, :admission_timeout} =
             peer_call(c.peer_b, Jido, :call, [FixedHome, c.address, Counter.add(4), [admission_timeout: 0]])

    assert :ok = peer_call(c.peer_b, Jido, :cast, [FixedHome, c.address, Counter.add(4)])

    peer_eventually(fn ->
      match?(%Status{agent_revision: 3}, peer_call(c.peer_b, Jido, :status, [FixedHome, c.address]))
    end)

    PeerHosts.stop(c.peer_a, FixedHome)
    assert {:error, :cluster_unavailable} = peer_call(c.peer_b, Jido, :call, [FixedHome, c.address, Counter.add(10)])
    PeerHosts.stop(c.peer_b, FixedHome)
    PeerHosts.stop(c.peer_b, __MODULE__)
  end

  test "a partition or lost reply gives no permission to replay or move", c do
    signal = Counter.add(5)
    assert :ok = peer_call(c.peer_a, TurnStartGate, :attach, [signal.id])
    call = Task.async(fn -> peer_call(c.peer_b, Jido, :call, [FixedHome, c.address, signal]) end)

    worker = peer_eventually(fn -> peer_call(c.peer_a, Process, :whereis, [TurnStartGate]) end)
    cookie = PeerHosts.disconnect(c)

    assert {:error, {:cluster_outcome_unknown, :noconnection}} = Task.await(call)

    assert {:error, {:cluster_outcome_unknown, :noconnection}} =
             peer_call(c.peer_b, Jido, :call, [FixedHome, c.address, Counter.add(100)])

    assert :ok = peer_call(c.peer_a, TurnStartGate, :release, [worker])
    assert {:error, :cluster_not_home} = peer_call(c.peer_b, Jido, :activate_agent, [FixedHome, c.address])

    assert {:ok, %TurnResult{agent_revision: 2}} =
             peer_call(c.peer_a, Jido, :call, [FixedHome, c.address, Counter.add(1)])

    PeerHosts.reconnect(c, cookie)
    assert %Status{agent_revision: 2} = peer_call(c.peer_b, Jido, :status, [FixedHome, c.address])
  end

  test "the caller stops waiting without cancelling the accepted Turn", c do
    signal = Counter.add(6)
    assert :ok = peer_call(c.peer_a, TurnStartGate, :attach, [signal.id])

    call =
      Task.async(fn ->
        peer_call(c.peer_b, Jido, :call, [
          FixedHome,
          c.address,
          signal,
          [timeout: 1_000, turn_id: "known-turn", result_handoff: true]
        ])
      end)

    worker = peer_eventually(fn -> peer_call(c.peer_a, Process, :whereis, [TurnStartGate]) end)
    assert {:error, {:cluster_outcome_unknown, :timeout}} = Task.await(call)
    assert :ok = peer_call(c.peer_a, TurnStartGate, :release, [worker])

    peer_eventually(fn ->
      match?(
        {:ok, %TurnResult{status: :committed, agent_revision: 1}},
        peer_call(c.peer_b, Jido, :turn_result, [FixedHome, c.address, "known-turn"])
      )
    end)
  end

  defp start(peer, opts) do
    assert {:ok, _pid} = peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {FixedHome, opts}])
  end
end
