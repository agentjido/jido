defmodule JidoTest.AgentServer.DurableTopologyTest do
  use JidoTest.Case, async: false
  @moduletag :tmp_dir
  @moduletag capture_log: true

  alias Jido.Agent.Directive, as: D
  alias Jido.AgentServer, as: Server
  alias JidoTest.DurableFixtures, as: F

  setup do
    start_supervised!({F.Probe, self()})
    :ok
  end

  defp member(server, name) do
    assert [pid] = Server.members(server, name)
    pid
  end

  defp replacement(c, id, old) do
    server =
      eventually(
        fn ->
          case Jido.whereis_agent(c.jido, id) do
            pid when is_pid(pid) and pid != old -> pid
            _ -> nil
          end
        end,
        timeout: 5_000
      )

    assert :ok = Server.await_ready(server)
    server
  end

  defp start(c) do
    assert {:ok, root} =
             Jido.start_agent(c.jido, F.Team,
               id: unique_id("team"),
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert :ok = Server.await_ready(root)
    root
  end

  for target <- [:member_server, :member_activation, :root_server, :root_activation] do
    test "#{target} loss retains member work, sibling commits, and topology identities", c do
      root = start(c)
      root_monitor = Process.monitor(root)
      worker = member(root, :worker)
      sibling = member(root, :sibling)
      root_id = Server.agent(root).id
      worker_id = Server.agent(worker).id
      sibling_id = Server.agent(sibling).id
      {:ok, topology} = Jido.Persistence.snapshot(Server.agent(root))
      assert {:ok, _, []} = Server.call(sibling, signal("increment"))
      pending = Server.submit(worker, signal("request", %{value: 0}))
      assert_receive {:durable_barrier, :step_6, action}, 5_000
      action_monitor = Process.monitor(action)

      victim =
        case unquote(target) do
          :member_server -> worker
          :member_activation -> Server.activation(worker)
          :root_server -> root
          :root_activation -> Server.activation(root)
        end

      monitor = Process.monitor(victim)
      Process.exit(victim, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^victim, :killed}, 5_000
      assert_receive {:DOWN, ^action_monitor, :process, ^action, _}, 5_000
      restored_worker = replacement(c, worker_id, worker)
      assert_receive {:durable_barrier, :step_6, _}, 5_000

      restored_root =
        if unquote(target) in [:root_server, :root_activation],
          do: replacement(c, root_id, root),
          else: root

      assert Process.alive?(restored_root),
             "Root stopped during #{unquote(target)} recovery: #{inspect(Process.info(self(), :messages))}"

      Process.demonitor(root_monitor, [:flush])
      assert {:ok, ^topology} = Jido.Persistence.snapshot(Server.agent(restored_root))
      assert member(restored_root, :worker) == restored_worker
      restored_sibling = member(restored_root, :sibling)
      assert Server.agent(restored_sibling).id == sibling_id
      assert Server.agent(restored_sibling).state.count == 1

      if unquote(target) in [:member_server, :member_activation],
        do: assert(restored_sibling == sibling)

      assert F.Probe.records() == Enum.to_list(1..6) ++ [6]
      F.Probe.release()

      eventually(
        fn ->
          Server.agent(restored_worker).state.count == 10
        end,
        timeout: 5_000
      )

      assert F.Probe.records() == Enum.to_list(1..6) ++ Enum.to_list(6..10)
      assert {:error, _} = Server.await(pending)
      assert :ok = Server.stop(restored_root)
      assert Jido.agent_count(c.jido) == 0
    end
  end

  test "removed and recreated member slots cannot recover old state or pending work", c do
    root = start(c)
    root_id = Server.agent(root).id
    old = member(root, :worker)
    old_id = Server.agent(old).id
    assert {:ok, _, []} = Server.call(old, signal("increment"))
    _pending = Server.submit(old, signal("request", %{value: 0}))
    assert_receive {:durable_barrier, :step_6, action}, 5_000
    monitor = Process.monitor(action)

    assert {:ok, _, [_, _, _]} =
             Server.call(
               root,
               signal("mutate", %{
                 directives: [
                   D.route_remove("request"),
                   D.connection_remove("request",
                     from: %{kind: :agent, name: :root},
                     to: %{kind: :agent, name: :worker}
                   ),
                   D.agent_remove(:worker)
                 ]
               })
             )

    assert :ok = Server.await_ready(root)
    assert_receive {:DOWN, ^monitor, :process, ^action, _}, 5_000

    assert {:ok, _, [_]} =
             Server.call(root, signal("mutate", %{directives: [D.agent_add(:worker, F.Worker)]}))

    assert :ok = Server.await_ready(root)
    new = member(root, :worker)
    assert Server.agent(new).id != old_id
    assert Server.agent(new).state.count == 0
    assert Server.status(new).durable_turn == nil
    new_id = Server.agent(new).id
    assert :ok = Server.hibernate(root)

    assert {:ok, awake} =
             Jido.thaw(c.jido, F.Team, root_id,
               persistence: {Jido.Persistence.File, path: c.tmp_dir}
             )

    assert :ok = Server.await_ready(awake)
    restored = member(awake, :worker)
    assert Server.agent(restored).id == new_id
    assert Server.status(restored).durable_turn == nil
    assert Server.agent(restored).state.count == 0
  end

  test "shrinking and growing member count retains only the surviving slot identities", c do
    root = start(c)
    assert Server.members(root, :missing) == []

    resize = fn count ->
      assert {:ok, _, [_]} =
               Server.call(
                 root,
                 signal("mutate", %{directives: [D.agent_update(:sibling, %{count: count})]})
               )

      assert :ok = Server.await_ready(root)
      members = Server.members(root, :sibling)
      assert length(members) == count
      members
    end

    [first, second, third] = resize.(3)
    retired_ids = Enum.map([second, third], &Server.agent(&1).id)
    assert {:ok, _, []} = Server.call(first, signal("increment"))
    assert {:ok, _, []} = Server.call(second, signal("increment"))
    assert [^first] = resize.(1)
    assert [^first, new_second, new_third] = resize.(3)
    assert Server.agent(first).state.count == 1

    for member <- [new_second, new_third] do
      assert Server.agent(member).id not in retired_ids
      assert Server.agent(member).state.count == 0
    end
  end
end
