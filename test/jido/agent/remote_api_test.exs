defmodule JidoTest.Agent.RemoteAPITest do
  use JidoTest.PeerCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteCounter
  alias JidoTest.RemoteAPIFixtures

  @tag peer_start_delay: 6_100
  test "admission uses the caller clock for both directions and request forms", c do
    {:ok, older} = peer_call(c.peer_a, Jido, :start_agent, [c.jido, RemoteCounter, [id: "older"]])

    {:ok, younger} =
      peer_call(c.peer_b, Jido, :start_agent, [c.jido, RemoteCounter, [id: "younger"]])

    clock_a = peer_call(c.peer_a, System, :monotonic_time, [:millisecond])
    clock_b = peer_call(c.peer_b, System, :monotonic_time, [:millisecond])
    assert abs(clock_a - clock_b) > 5_000

    for {caller, owner, pid} <- [{c.peer_b, c.peer_a, older}, {c.peer_a, c.peer_b, younger}] do
      assert {:ok, %{state: %{value: 1}}} = peer_call(caller, RemoteCounter, :record, [pid, 1])
      assert peer_call(caller, Server, :alive?, [pid])

      for kind <- [:call, :request] do
        :ok = peer_call(owner, :sys, :suspend, [pid])

        try do
          assert :timeout = peer_call(caller, RemoteAPIFixtures, :record, [kind, pid, 2, 50])
        after
          :ok = peer_call(owner, :sys, :resume, [pid])
        end

        # A snapshot call is ordered after the request already in the mailbox.
        assert %{state_version: 1, agent: %{state: %{value: 1}}} =
                 peer_call(owner, Server, :snapshot, [pid])
      end

      assert {:reply, {:ok, %{state: %{value: 3}}}} =
               peer_call(caller, RemoteAPIFixtures, :record, [:request, pid, 3, :infinity])

      assert {:ok, %{state: %{value: 4}}} =
               peer_call(caller, RemoteAPIFixtures, :record, [:call, pid, 4, :infinity])

      :ok = peer_call(owner, Server, :stop, [pid])
      refute peer_call(caller, Server, :alive?, [pid])
    end
  end
end
