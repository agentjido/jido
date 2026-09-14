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
    assert {:ok, _} = Jido.AgentServer.call(server, ControlledAgent.signal(1))
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

      assert {:ok, _} = Peers.call(peer, :work, [server, revision * 10])
      {signal_id, caller, worker} = Peers.call(peer, :hold, [server])
      events = Peers.call(peer, :events)

      starts =
        for {_, [:jido, :agent, :turn, :start], _, meta} <- events,
            meta.source_signal_id == signal_id,
            do: meta

      stops =
        for {_, [:jido, :agent, :turn, ending], _, meta} <- events,
            ending in [:stop, :exception],
            meta.source_signal_id == signal_id,
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
        assert {:ok, _} = Peers.call(peer, :work, [server, 7])
        assert Peers.call(peer, :snapshot, [server]).state_version == 1

        assert Enum.any?(Peers.call(peer, :events), fn
                 {_, [:jido, :agent, :turn, :stop], _, %{committed?: true}} -> true
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

  test "a sustained partition interrupts remote work and closes the old child request", c do
    left = Peers.start!(c.cookie, &on_exit/1)
    right = Peers.start!(c.cookie, &on_exit/1)
    {peer_a, node_a} = left
    {peer_b, node_b} = right
    parent_dir = Path.join(c.tmp_dir, "partition-parent")
    child_dir = Path.join(c.tmp_dir, "partition-child")

    :ok = Peers.call(peer_a, :start, [c.namespace, parent_dir])
    :ok = Peers.call(peer_b, :start, [c.namespace, child_dir])
    assert true == :peer.call(peer_a, Node, :connect, [node_b])
    assert true == :peer.call(peer_b, Node, :connect, [node_a])
    :ok = Peers.call(peer_a, :watch, [node_b])
    :ok = Peers.call(peer_b, :watch, [node_a])

    assert {:ok, parent} = Peers.call(peer_a, :activate_parent, ["partition-parent"])
    assert {:ok, _} = Peers.call(peer_a, :create_worker, [parent, node_b])
    :ok = Peers.call(peer_a, :await_event, ["partition-parent", [:jido, :agent, :turn, :stop], 2])
    assert %{pid: child_pid, id: child_id} = Peers.call(peer_a, :child, [parent])
    assert node(child_pid) == node_b

    {signal_id, caller, worker, _gate} = Peers.call(peer_b, :hold_releasable, [child_pid])

    for pid <- [child_pid, caller, worker],
        do: assert(:ok = Peers.call(peer_b, :watch_pid, [pid]))

    before = Peers.call(peer_b, :snapshot, [child_pid])
    assert before.state_version == 0
    assert Peers.call(peer_b, :pool_size) == 1

    :ok = Peers.partition(left, right)
    :ok = Peers.call(peer_a, :await_event, ["partition-parent", [:jido, :agent, :turn, :stop], 3])

    for pid <- [child_pid, caller, worker],
        do: assert(:ok = Peers.call(peer_b, :await_pid_down, [pid]))

    assert [%{child_id: ^child_id, observation: :unreachable, reason: :noconnection}] =
             Peers.call(peer_a, :observations, [parent])

    assert Peers.call(peer_a, :child, [parent]) == nil
    assert Peers.call(peer_b, :pool_size) == 0
    assert :peer.call(peer_a, Node, :list, []) == []
    assert :peer.call(peer_b, Node, :list, []) == []
    assert {:ok, saved, 0} = Peers.call(peer_b, :saved, [child_dir, c.namespace, child_id])
    assert saved.state.value == 0

    remote_events = Peers.call(peer_b, :events)

    assert Enum.any?(remote_events, fn
             {_, [:jido, :agent, :turn, :start], _, %{source_signal_id: ^signal_id}} -> true
             _ -> false
           end)

    assert Enum.any?(remote_events, fn
             {_, [:jido, :agent, :turn, :stop], _,
              %{source_signal_id: ^signal_id, status: :cancelled, committed?: false}} ->
               true

             _ ->
               false
           end)

    :ok = Peers.rejoin(left, right, c.cookie)
    assert {:ok, _} = Peers.call(peer_a, :create_worker, [parent, node_b])
    :ok = Peers.call(peer_a, :await_event, ["partition-parent", [:jido, :agent, :turn, :stop], 4])
    assert Peers.call(peer_a, :child, [parent]) == nil
    assert {:ok, _} = Peers.call(peer_a, :create_worker, [parent, node_b])
    :ok = Peers.call(peer_a, :await_event, ["partition-parent", [:jido, :agent, :turn, :stop], 6])
    assert %{pid: replacement, id: ^child_id} = Peers.call(peer_a, :child, [parent])
    refute replacement == child_pid
    assert node(replacement) == node_b

    stale =
      {:agent_child_online, child_pid, child_id, ControlledAgent, nil, :worker, %{}}

    assert %{worker: %{pid: ^replacement}} =
             :peer.call(peer_a, JidoTest.RemoteChildFixtures, :inject_online_and_read_children, [
               parent,
               stale
             ])

    assert :ok = Peers.call(peer_b, :watch_pid, [replacement])
    assert :ok = Peers.call(peer_a, :stop_child, [parent])
    assert :ok = Peers.call(peer_b, :await_pid_down, [replacement])
    assert :ok = Peers.call(peer_a, :stop, [parent])
    assert Peers.call(peer_a, :pool_size) == 0
    assert Peers.call(peer_b, :pool_size) == 0
    Observability.measure(c.observer, %{partitioned_nodes: 2, interrupted_remote_turns: 1})
  end

  test "a child started after its spawn reply is lost cannot be adopted after a partition", c do
    left = Peers.start!(c.cookie, &on_exit/1)
    right = Peers.start!(c.cookie, &on_exit/1)
    {peer_a, node_a} = left
    {peer_b, node_b} = right
    :ok = Peers.call(peer_a, :start, [c.namespace, Path.join(c.tmp_dir, "late-parent")])
    :ok = Peers.call(peer_b, :start, [c.namespace, Path.join(c.tmp_dir, "late-child")])
    assert true == :peer.call(peer_a, Node, :connect, [node_b])
    assert true == :peer.call(peer_b, Node, :connect, [node_a])
    :ok = Peers.call(peer_a, :watch, [node_b])
    :ok = Peers.call(peer_b, :watch, [node_a])
    assert {:ok, parent} = Peers.call(peer_a, :activate_startup_parent, ["late-parent", 100])
    supervisor = Jido.agent_supervisor_name(JidoTest.System.PeerInstance)
    assert :ok = :peer.call(peer_b, :sys, :suspend, [supervisor])

    try do
      assert {:ok, _} = Peers.call(peer_a, :request_spawn, [parent, node_b])

      assert :ok =
               Peers.call(peer_a, :await_event, [
                 "late-parent",
                 [:jido, :agent, :directive, :stop],
                 1
               ])

      _status = Peers.call(peer_a, :status, [parent])
      error = Peers.call(peer_a, :startup_error, ["late-parent"])

      request =
        case error do
          {{:child_spawn_indeterminate, :worker, ^node_b, request, :timeout},
           %{status: :indeterminate}} ->
            request

          other ->
            directives =
              for {_, event, measures, meta} <- Peers.call(peer_a, :events),
                  Enum.at(event, 2) == :directive,
                  do: {event, Map.take(meta, [:status, :error_type, :agent_id]), measures}

            flunk(
              "startup result=#{inspect(other)}; directives=#{inspect(directives, limit: :infinity)}"
            )
        end

      assert {generation, ref} = request
      assert is_integer(generation) and is_reference(ref)

      Observability.service_log(c.observer, :peer, "Remote spawn reply lost", %{
        request_generation: generation
      })

      assert :ok = :peer.call(peer_a, :sys, :suspend, [parent])

      try do
        assert :ok = :peer.call(peer_b, :sys, :resume, [supervisor])

        assert :ok =
                 Peers.call(peer_b, :await_event, [
                   "late-parent/worker",
                   [:jido, :agent, :lifecycle, :stop],
                   1
                 ])

        child_pid = Peers.call(peer_b, :whereis, ["late-parent/worker"])
        assert is_pid(child_pid)
        assert :ok = Peers.call(peer_b, :watch_pid, [child_pid])
        :ok = Peers.partition(left, right)
        assert :ok = Peers.call(peer_b, :await_pid_down, [child_pid])
        assert :peer.call(peer_a, Node, :list, []) == []
        assert :peer.call(peer_b, Node, :list, []) == []
      after
        assert :ok = :peer.call(peer_a, :sys, :resume, [parent])
      end
    after
      :peer.call(peer_b, :sys, :resume, [supervisor])
    end

    assert Peers.call(peer_a, :child, [parent]) == nil
    assert Peers.call(peer_b, :whereis, ["late-parent/worker"]) == nil
    assert Peers.call(peer_b, :pool_size) == 0
    :ok = Peers.rejoin(left, right, c.cookie)

    assert {:ok, _} = Peers.call(peer_a, :request_spawn, [parent, node_b])

    assert :ok =
             Peers.call(peer_a, :await_event, [
               "late-parent",
               [:jido, :agent, :directive, :stop],
               2
             ])

    assert Peers.call(peer_a, :child, [parent]) == nil
    assert {:ok, _} = Peers.call(peer_a, :request_spawn, [parent, node_b])

    assert :ok =
             Peers.call(peer_a, :await_event, [
               "late-parent",
               [:jido, :agent, :turn, :stop],
               4
             ])

    assert %{pid: replacement, id: "late-parent/worker"} = Peers.call(peer_a, :child, [parent])
    assert node(replacement) == node_b
    assert Peers.call(peer_b, :pool_size) == 1
    assert :ok = Peers.call(peer_b, :watch_pid, [replacement])
    assert :ok = Peers.call(peer_a, :stop_child, [parent])
    assert :ok = Peers.call(peer_b, :await_pid_down, [replacement])
    assert :ok = Peers.call(peer_a, :stop, [parent])
    assert Peers.call(peer_a, :pool_size) == 0
    assert Peers.call(peer_b, :pool_size) == 0
    Observability.measure(c.observer, %{late_spawn_requests: 1, closed_spawn_requests: 1})
  end
end
