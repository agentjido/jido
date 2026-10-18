Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/peers.exs", __DIR__)

defmodule JidoTest.System.PeerScenarios do
  use JidoTest.System.Case, async: false
  @moduletag :system
  @moduletag adapter: :file
  alias JidoTest.System.{ControlledAgent, Observability, Peers}

  setup c do
    # The host observer remains active while isolated BEAMs come and go.
    server = start_agent(c, module: ControlledAgent)
    assert {:ok, _, _} = Jido.AgentServer.call(server, ControlledAgent.signal(1))
    stop_agent(c, server)
    {:ok, cookie: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)}
  end

  @tag scenario: :burn_in
  test "three complete BEAM replacements restore one File checkpoint without replaying held work",
       c do
    directory = Path.join(c.tmp_dir, "peer-checkpoints")
    {witness, _} = Peers.start!(c.cookie, &on_exit/1)

    :ok =
      Peers.call(witness, :start, [c.namespace <> "-witness", Path.join(c.tmp_dir, "witness")])

    for revision <- 1..3 do
      {peer, peer_node} = Peers.start!(c.cookie, &on_exit/1)
      assert true == :peer.call(witness, Node, :connect, [peer_node])
      assert :ok = Peers.call(witness, :watch, [peer_node])
      assert :ok = Peers.call(peer, :start, [c.namespace, directory])

      assert {:ok, server} =
               Peers.call(peer, :activate, [
                 "same-agent",
                 if(revision == 1, do: false, else: :required)
               ])

      before = Peers.call(peer, :snapshot, [server])

      assert {before.state_version, before.agent.state.value} ==
               {revision - 1, (revision - 1) * 10}

      assert {:ok, _, _} = Peers.call(peer, :work, [server, revision * 10])
      {signal_id, caller, worker} = Peers.call(peer, :hold, [server])
      events = Peers.call(peer, :events)

      starts =
        for {_, [:jido, :agent_server, :turn, :start], _, meta} <- events,
            meta.signal_id == signal_id,
            do: meta

      stops =
        for {_, [:jido, :agent_server, :turn, ending], _, meta} <- events,
            ending in [:stop, :exception],
            meta.signal_id == signal_id,
            do: meta

      assert [%{turn_id: turn_id}] = starts
      assert is_binary(turn_id) and stops == []
      assert node(caller) == peer_node and node(worker) == peer_node
      assert :ok = Peers.crash(peer)
      assert :ok = Peers.call(witness, :await_down, [peer_node])

      Observability.service_log(c.observer, :peer, "Node loss interrupted a held Turn", %{
        turn_id: turn_id,
        revision: revision
      })
    end

    {final, _} = Peers.start!(c.cookie, &on_exit/1)
    :ok = Peers.call(final, :start, [c.namespace, directory])
    {:ok, restored} = Peers.call(final, :activate, ["same-agent", :required])
    snapshot = Peers.call(final, :snapshot, [restored])
    assert {snapshot.state_version, snapshot.agent.state.value} == {3, 30}
    assert :ok = Peers.stop(final)
    assert :ok = Peers.stop(witness)
    assert_empty_agent_pool(c)
    assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

    Observability.measure(c.observer, %{full_beam_replacements: 3, node_loss_interrupted_turns: 3})
  end

  @tag :research
  @tag skip: "Cluster-exclusive ownership is outside the V3 beta scope (DIST-03)"
  test "connected peers must not claim an exclusive owner without a cluster authority contract",
       c do
    [{left, node_left}, {right, node_right}] =
      for _ <- 1..2, do: Peers.start!(c.cookie, &on_exit/1)

    assert true == :peer.call(left, Node, :connect, [node_right])
    assert true == :peer.call(right, Node, :connect, [node_left])

    owners =
      for {peer, name} <- [{left, "left"}, {right, "right"}] do
        :ok = Peers.call(peer, :start, [c.namespace, Path.join(c.tmp_dir, name)])
        {:ok, server} = Peers.call(peer, :activate, ["same-logical-id", false])
        assert {:ok, _, _} = Peers.call(peer, :work, [server, 7])
        assert Peers.call(peer, :snapshot, [server]).state_version == 1

        assert Enum.any?(Peers.call(peer, :events), fn
                 {_, [:jido, :agent_server, :turn, :stop], _, %{committed?: true}} -> true
                 _ -> false
               end)

        server
      end

    for peer <- [left, right], do: Peers.stop(peer)
    Observability.measure(c.observer, %{simultaneous_cluster_owners: length(owners)})
    assert_empty_agent_pool(c)
    assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

    assert length(owners) == 1,
           "SYSTEM-CLUSTER-01: connected peers activated the same namespace and Agent ID. Local registration and separate File stores do not provide exclusive cluster ownership. DIST-03 remains unchanged."
  end
end
