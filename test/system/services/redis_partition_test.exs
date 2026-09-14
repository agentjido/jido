Code.require_file("../support/case.exs", __DIR__)
Code.require_file("../support/peers.exs", __DIR__)

defmodule JidoTest.System.RedisPartition do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :redis
  alias JidoTest.System.{ControlledAgent, Observability, Peers}

  setup c do
    # Keep the host observer active while the two isolated peers use the same
    # real Redis checkpoint store through their independent control channels.
    server = start_agent(c, module: ControlledAgent)
    assert {:ok, _} = Jido.AgentServer.call(server, ControlledAgent.signal(1))
    stop_agent(c, server)
    {:ok, cookie: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)}
  end

  test "a partitioned old activation cannot overwrite a replacement revision", c do
    left = Peers.start!(c.cookie, &on_exit/1)
    right = Peers.start!(c.cookie, &on_exit/1)
    {peer_a, node_a} = left
    {peer_b, node_b} = right
    {:ok, supervisor} = ExUnit.fetch_test_supervisor()

    {_, redis, _, _} =
      Enum.find(Supervisor.which_children(supervisor), fn {id, _, _, _} ->
        id == JidoTest.System.RedisServer
      end)

    {socket, _os_pid} = GenServer.call(redis, :connection)
    assert :ok = Peers.call(peer_a, :start_redis, [c.namespace, socket])
    assert :ok = Peers.call(peer_b, :start_redis, [c.namespace, socket])
    assert true == :peer.call(peer_a, Node, :connect, [node_b])
    assert true == :peer.call(peer_b, Node, :connect, [node_a])
    assert :ok = Peers.call(peer_a, :watch, [node_b])
    assert :ok = Peers.call(peer_b, :watch, [node_a])

    assert {:ok, old} = Peers.call(peer_a, :activate, ["partitioned-agent", false])
    assert {:ok, _} = Peers.call(peer_a, :work, [old, 1])

    assert %{state_version: 1, agent: %{state: %{value: 1}}} =
             Peers.call(peer_a, :snapshot, [old])

    {signal_id, caller, worker, gate} = Peers.call(peer_a, :hold_releasable, [old])
    assert :ok = Peers.call(peer_a, :watch_pid, [old])
    assert :ok = Peers.call(peer_a, :watch_pid, [caller])
    assert Peers.call(peer_a, :pool_size) == 1
    :ok = Peers.partition(left, right)

    assert {:ok, replacement} = Peers.call(peer_b, :activate, ["partitioned-agent", :required])
    assert Peers.call(peer_b, :snapshot, [replacement]).state_version == 1
    assert {:ok, _} = Peers.call(peer_b, :work, [replacement, 2])

    assert %{state_version: 2, agent: %{state: %{value: 2}}} =
             Peers.call(peer_b, :snapshot, [replacement])

    assert :peer.call(peer_a, Node, :list, []) == []
    assert :peer.call(peer_b, Node, :list, []) == []
    :ok = Peers.rejoin(left, right, c.cookie)
    assert :ok = :peer.call(peer_a, Process, :send, [worker, {:release_work, gate}, []])

    assert {:error, {:persistence_failed, :conflict}} =
             Peers.call(peer_a, :await_work_result, [signal_id])

    assert :ok = Peers.call(peer_a, :await_pid_down, [old])
    assert :ok = Peers.call(peer_a, :await_pid_down, [caller])
    assert Peers.call(peer_a, :pool_size) == 0

    assert {:ok, saved, 2} =
             Jido.Persistence.load_agent_with_revision(
               c.store,
               ControlledAgent,
               "partitioned-agent",
               instance: JidoTest.System.PeerInstance,
               namespace: c.namespace
             )

    assert saved.state.value == 2
    assert Peers.call(peer_b, :snapshot, [replacement]).agent == saved
    assert :ok = Peers.call(peer_b, :stop, [replacement])
    assert Peers.call(peer_b, :pool_size) == 0
    assert_empty_agent_pool(c)
    assert JidoTest.RecoverableDeliverySink.attempts(c.jido) == []

    old_events = Peers.call(peer_a, :events)
    new_events = Peers.call(peer_b, :events)

    assert Enum.any?(old_events, fn
             {_, [:jido, :agent, :turn, :stop], _,
              %{source_signal_id: ^signal_id, committed?: false}} ->
               true

             _ ->
               false
           end)

    assert Enum.any?(new_events, fn
             {_, [:jido, :agent, :turn, :stop], _, %{committed?: true}} -> true
             _ -> false
           end)

    Observability.service_log(c.observer, :redis, "Old partitioned write was fenced", %{
      revision: 2,
      agent_id: "partitioned-agent"
    })

    Observability.measure(c.observer, %{partitioned_nodes: 2, rejected_stale_writes: 1})
  end
end
