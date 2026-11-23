Code.require_file("example.ex", __DIR__)
Code.require_file("../support/ticket.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)
Code.require_file("support/mnesia_hosts.exs", __DIR__)
Code.require_file("support/persistence_gate.ex", __DIR__)

defmodule Jido.Examples.DistributedAgents.NativeTicketRecoveryTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer.{Status, TurnResult}
  alias Jido.Examples.DistributedAgents.{MnesiaHosts, NativeTicketRecovery, PeerHosts, PersistenceGate, Ticket}
  alias Jido.Exec.Wait

  @instance Jido.Examples.DistributedAgents.NativeTicketHost
  @sources Enum.map(["example.ex", "../support/ticket.ex", "support/persistence_gate.ex"], &Path.expand(&1, __DIR__))

  setup c do
    PeerHosts.load([c.peer_a, c.peer_b], @sources)
    table = :native_ticket_records
    profile = MnesiaHosts.open(c, table)
    address = Address.new!(namespace: "examples/distribution/native-ticket", id: "ticket-42")
    first = {c.node_a, "first"}
    second = {c.node_b, "second"}

    assert :ok =
             peer_call(c.peer_b, Jido, :change_cluster_home, [profile, address.namespace, :not_found, first])

    initial_opts = NativeTicketRecovery.instance_options(@instance, address.namespace, table, first)
    moved_opts = NativeTicketRecovery.instance_options(@instance, address.namespace, table, second)
    PeerHosts.start(c.peer_a, initial_opts)
    PeerHosts.start(c.peer_b, initial_opts)
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [@instance, address, Ticket])

    %{
      address: address,
      table: table,
      profile: profile,
      first: first,
      second: second,
      initial_opts: initial_opts,
      moved_opts: moved_opts
    }
  end

  test "a stopped-home move preserves the waiting approval and refuses stale startup", c do
    assert {:ok, %TurnResult{status: :waiting, turn_id: "review", agent_activation_id: old, waits: waits}} =
             open(c, "review")

    PeerHosts.stop(c.peer_b, @instance)
    assert inspect(start(c.peer_b, c.moved_opts)) =~ "cluster_home_mismatch"
    PeerHosts.stop(c.peer_a, @instance)

    move(c)
    PeerHosts.start(c.peer_b, c.moved_opts)
    assert inspect(start(c.peer_a, c.initial_opts)) =~ "cluster_home_mismatch"
    PeerHosts.start(c.peer_a, c.moved_opts)

    assert {:ok, %TurnResult{status: :committed, turn_id: "review", agent_activation_id: new}} =
             peer_call(c.peer_a, Jido, :call, [@instance, c.address, Ticket.approve(c.address.id)])

    assert old != new

    assert {:ok, %TurnResult{turn_id: "review"}} =
             peer_call(c.peer_a, Jido, :turn_result, [@instance, c.address, "review"])

    assert :ok = peer_call(c.peer_b, Jido, :acknowledge_turn_result, [@instance, c.address, "review"])
    %{data: %{deadline: deadline}} = occurrence = wake_signal("review", waits)
    peer_eventually(fn -> System.system_time(:millisecond) >= deadline end, timeout: 7_000)
    assert {:error, :stale_wait} = peer_call(c.peer_a, Jido, :call, [@instance, c.address, occurrence])
    assert %Status{agent_revision: 1} = peer_call(c.peer_a, Jido, :status, [@instance, c.address])
    assert saved_ticket(c).state.status == :approved

    assert 0 == peer_call(c.peer_a, Jido, :resident_agent_count, [@instance])
    PeerHosts.stop(c.peer_a, @instance)
    PeerHosts.stop(c.peer_b, @instance)
  end

  test "B restores an overdue deadline after A dies immediately after acknowledgement", c do
    assert {:ok, %TurnResult{status: :waiting, durability: :durable, agent_activation_id: old, waits: waits}} =
             open(c, "deadline")

    # If the deadline fires on A, hold its first checkpoint before it reaches Mnesia.
    assert :ok = peer_call(c.peer_a, PersistenceGate, :attach, [c.address.id])
    PeerHosts.kill(c.peer_a)

    %{data: %{wait_id: wait_id, deadline: deadline}} = occurrence = wake_signal("deadline", waits)
    assert System.system_time(:millisecond) < deadline
    assert saved_ticket(c).state.status == :open
    expected_wake = %{agent_ref: Address.to_map!(c.address), turn_id: "deadline", wait_id: wait_id, deadline: deadline}
    assert expected_wake in MnesiaHosts.saved_wakes(c, c.profile, c.address.namespace)
    PeerHosts.stop(c.peer_b, @instance)
    move(c)

    # Test the overdue recovery path. No request activates the Agent on B.
    peer_eventually(fn -> System.system_time(:millisecond) >= deadline end, timeout: 7_000)
    PeerHosts.start(c.peer_b, c.moved_opts)

    result =
      peer_eventually(fn ->
        case peer_call(c.peer_b, Jido, :turn_result, [@instance, c.address, "deadline"]) do
          {:ok, result} -> result
          {:error, :not_found} -> nil
        end
      end)

    assert %TurnResult{
             status: :committed,
             turn_id: "deadline",
             agent_revision: 1,
             agent_address: address,
             agent_activation_id: new
           } = result

    assert address == c.address
    assert old != new

    assert {:ok, worker} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, c.address])
    assert peer_call(c.peer_b, Jido.AgentServer, :snapshot, [worker]).agent.state.status == :escalated

    assert {:ok, ^result} = peer_call(c.peer_b, Jido, :turn_result, [@instance, c.address, "deadline"])

    assert {:error, :result_acknowledgement_required} =
             peer_call(c.peer_b, Jido, :call, [@instance, c.address, occurrence])

    assert :ok = peer_call(c.peer_b, Jido, :acknowledge_turn_result, [@instance, c.address, "deadline"])
    assert {:error, :not_found} = peer_call(c.peer_b, Jido, :turn_result, [@instance, c.address, "deadline"])

    assert {:ok, %TurnResult{turn_id: "deadline", status: :committed, agent_revision: 1}} =
             peer_call(c.peer_b, Jido, :call, [@instance, c.address, occurrence])

    assert %Status{agent_revision: 1} = peer_call(c.peer_b, Jido, :status, [@instance, c.address])
    PeerHosts.stop(c.peer_b, @instance)
  end

  test "a live store partition cannot turn the ingress peer into a home", c do
    assert {:ok, %TurnResult{status: :committed, agent_revision: 1}} =
             peer_call(c.peer_b, Jido, :call, [@instance, c.address, Ticket.note("original")])

    other = %{c.address | id: "ticket-isolated"}
    assert {:ok, ^other} = peer_call(c.peer_a, Jido, :create_agent, [@instance, other, Ticket])
    assert :ok = peer_call(c.peer_a, PersistenceGate, :attach, [c.address.id])

    pending =
      Task.async(fn ->
        peer_call(c.peer_b, Jido, :call, [@instance, c.address, Ticket.note("interrupted"), 3_000])
      end)

    writer = peer_eventually(fn -> peer_call(c.peer_a, Process, :whereis, [PersistenceGate]) end)
    cookie = PeerHosts.disconnect(c)
    assert {:error, {:cluster_outcome_unknown, :noconnection}} = Task.await(pending)
    assert :ok = peer_call(c.peer_a, PersistenceGate, :release, [writer])
    assert {:error, :cluster_not_home} = peer_call(c.peer_b, Jido, :activate_agent, [@instance, c.address])

    refute match?(
             {:ok, %TurnResult{status: :committed}},
             peer_call(c.peer_a, Jido, :call, [
               @instance,
               other,
               Ticket.note("during isolation"),
               1_000
             ])
           )

    assert :ok = peer_call(c.peer_b, Jido, :check_cluster_home, [c.profile, c.address.namespace, c.first])
    assert saved_ticket(c).state.last_note == "original"

    # Rejoin using B's canonical table and restart the old home configuration.
    PeerHosts.stop(c.peer_a, @instance)
    assert :stopped = peer_call(c.peer_a, :mnesia, :stop, [])
    PeerHosts.reconnect(c, cookie)
    MnesiaHosts.join_client(c, c.table)
    PeerHosts.start(c.peer_a, c.initial_opts)
    assert saved_ticket(c).state.last_note == "original"
    assert saved_ticket(%{c | address: other}).state.last_note == nil

    assert {:ok, %TurnResult{status: :committed, agent_revision: 2}} =
             peer_call(c.peer_b, Jido, :call, [@instance, c.address, Ticket.note("after reconnect")])

    PeerHosts.stop(c.peer_a, @instance)
    PeerHosts.stop(c.peer_b, @instance)
  end

  defp open(c, id), do: peer_call(c.peer_b, NativeTicketRecovery, :open, [@instance, c.address, id])

  defp saved_ticket(c) do
    assert {:ok, ticket} =
             peer_call(c.peer_b, Jido.Persistence, :load_agent, [
               c.profile,
               Ticket,
               c.address.id,
               [namespace: c.address.namespace]
             ])

    ticket
  end

  defp wake_signal(turn_id, [%Wait{id: wait_id}] = waits) do
    Jido.Signal.new!("jido.durable.wake", %{turn_id: turn_id, wait_id: wait_id, deadline: Wait.next_deadline(waits)},
      source: "/examples/distribution/native-ticket"
    )
  end

  defp move(c) do
    assert :ok =
             peer_call(c.peer_b, NativeTicketRecovery, :move_after_stop, [
               c.profile,
               c.address.namespace,
               c.first,
               c.second
             ])
  end

  defp start(peer, opts), do: peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])
end
