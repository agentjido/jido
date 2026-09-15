defmodule JidoTest.Topology.ControllerColdRestoreTest do
  use JidoTest.PeerCase, async: false
  alias Jido.Agent.Ref
  alias Jido.Persistence
  alias Jido.Persistence.ETS
  alias Jido.Topology.{Builder, Controller}
  alias JidoTest.TopologyRestoreProbe

  test "loads an Agent definition before safe checkpoint decoding on a cold remote host", c do
    namespace = "cold-topology-restore"
    jido = JidoTest.ColdTopologyInstance
    store = {ETS, table: :cold_topology_restore}

    instance =
      Builder.new(name: "cold_restore")
      |> Builder.agent(:worker, TopologyRestoreProbe, node: c.node_b)
      |> Builder.build!(id: "cold")

    id = hd(Map.values(instance.plan.agents)).id
    ref = Ref.new!(namespace: namespace, id: id)

    for peer <- [c.peer_a, c.peer_b] do
      assert {:ok, _} =
               peer_call(peer, Supervisor, :start_child, [
                 Jido.Supervisor,
                 {Jido, name: jido, namespace: namespace, persistence: store}
               ])
    end

    {:ok, agent} =
      peer_call(c.peer_a, TopologyRestoreProbe, :new, [
        [id: id, state: %{topology_cold_restore_count: 7}]
      ])

    agent = %{
      agent
      | vsn: nil,
        metadata: %{"jido.topology" => %{id: instance.id, key: "agent/worker"}}
    }

    assert :ok =
             peer_call(c.peer_a, Persistence, :save_agent, [
               store,
               agent,
               [instance: jido, namespace: namespace]
             ])

    assert {:ok, bytes} =
             peer_call(c.peer_a, ETS, :get, [Persistence.agent_key(ref), elem(store, 1)])

    assert :ok =
             peer_call(c.peer_b, ETS, :put, [Persistence.agent_key(ref), bytes, elem(store, 1)])

    refute peer_call(c.peer_b, :code, :is_loaded, [TopologyRestoreProbe])

    assert {:ok, controller} =
             peer_call(c.peer_a, Supervisor, :start_child, [
               Jido.Supervisor,
               {Controller, jido: jido, topology: instance, repair: :manual}
             ])

    peer_eventually(fn ->
      peer_call(c.peer_a, Controller, :status, [controller]).active == 0
    end)

    assert %{status: :ready, errors: %{}} = peer_call(c.peer_a, Controller, :status, [controller])
    restored = peer_call(c.peer_a, Controller, :whereis_agent, [controller, :worker])

    assert %{agent: %{state: %{topology_cold_restore_count: 7}}} =
             peer_call(c.peer_b, Jido.AgentServer, :snapshot, [restored])

    assert :ok =
             peer_call(c.peer_a, Supervisor, :terminate_child, [
               Jido.Supervisor,
               {Controller, instance.id}
             ])

    peer_eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [restored]) end)
  end
end
