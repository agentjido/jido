defmodule Jido.AgentServer.DurableTopologyTest do
  use Jido.Test.Case, async: false
  @moduletag :tmp_dir
  @moduletag capture_log: true
  @moduletag obligation: [
               "jido.agent_server.composition.I6",
               "jido.agent_server.composition.I7"
             ]

  alias Jido.AgentServer, as: Server
  alias Jido.Test.AgentServer.DurableFixtures, as: F

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
end
