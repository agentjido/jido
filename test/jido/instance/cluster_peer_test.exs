defmodule Jido.Instance.ClusterPeerTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  alias Jido.Instance.Names
  alias Jido.Test.AgentServer.RuntimeFixtures.RuntimeAgent

  test "a cached Worker refuses admission while an instance dependency is down", c do
    instance = __MODULE__.Home
    namespace = "cluster-peer-readiness"
    profile = {Jido.Persistence.ETS, table: __MODULE__}
    home = {c.node_a, "generation"}

    assert :ok = peer_call(c.peer_a, Jido, :change_cluster_home, [profile, namespace, :not_found, home])

    opts = [
      name: instance,
      namespace: namespace,
      persistence: profile,
      cluster: [home: c.node_a, generation: "generation"]
    ]

    assert {:ok, _pid} = peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])
    assert {:ok, address} = peer_call(c.peer_a, Jido, :agent_address, [instance, "worker"])
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [instance, address, RuntimeAgent])
    assert {:ok, worker} = peer_call(c.peer_a, Jido, :activate_agent, [instance, address])
    signal = Jido.Signal.new!("cron.tick", %{}, source: "/test/cluster")

    assert :ok = peer_call(c.peer_a, Supervisor, :terminate_child, [instance, Names.runtime_store(instance)])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido.AgentServer, :call, [worker, signal])
    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido, :call, [instance, address, signal])
    assert %{agent_revision: 0} = peer_call(c.peer_a, Jido.AgentServer, :status, [worker])
  end

  test "direct lifecycle calls refuse work while Wake is unavailable", c do
    instance = __MODULE__.WakeUnavailable
    namespace = "cluster-peer-wake-unavailable"
    profile = {Jido.Persistence.ETS, table: __MODULE__}
    home = {c.node_a, "generation"}

    assert :ok = peer_call(c.peer_a, Jido, :change_cluster_home, [profile, namespace, :not_found, home])

    opts = [
      name: instance,
      namespace: namespace,
      persistence: profile,
      cluster: [home: c.node_a, generation: "generation"]
    ]

    assert {:ok, _pid} = peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])
    assert {:ok, address} = peer_call(c.peer_a, Jido, :agent_address, [instance, "worker"])
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [instance, address, RuntimeAgent])
    assert :ok = peer_call(c.peer_a, Supervisor, :terminate_child, [instance, Jido.Instance.Wake])

    assert {:error, :cluster_unavailable} = peer_call(c.peer_a, Jido, :activate_agent, [instance, address])

    new_address = %{address | id: "not-created"}

    assert {:error, :cluster_unavailable} =
             peer_call(c.peer_a, Jido, :create_agent, [instance, new_address, RuntimeAgent])
  end
end
