defmodule Jido.AgentServer.RemoteAPITest do
  use JidoTest.PeerCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteCounter
  alias JidoTest.RemoteAPIFixtures

  test "remote attachment and adoption preserve live and dead PID results", c do
    {:ok, parent} =
      peer_call(c.peer_a, Jido, :start_agent, [c.jido, RemoteCounter, [id: "parent"]])

    {:ok, child} = peer_call(c.peer_b, Jido, :start_agent, [c.jido, RemoteCounter, [id: "child"]])

    assert :ok = peer_call(c.peer_b, Server, :attach, [child, parent])
    assert peer_call(c.peer_b, Server, :status, [child]).runtime.lifecycle.attached == 1
    assert :ok = peer_call(c.peer_b, Server, :detach, [child, parent])
    assert :ok = peer_call(c.peer_a, Server, :adopt_child, [parent, child, :child])
    assert peer_call(c.peer_b, Server, :status, [child]).runtime.parent.pid == parent
    assert peer_call(c.peer_a, Server, :children, [parent]).child.pid == child

    :ok = peer_call(c.peer_b, Server, :stop, [child])
    assert {:error, :owner_not_alive} = peer_call(c.peer_a, Server, :attach, [parent, child])

    assert {:error, {:adopt_child_failed, :child_not_alive}} =
             peer_call(c.peer_a, Server, :adopt_child, [parent, child, :dead])

    assert peer_call(c.peer_a, Server, :alive?, [parent])
  end

  test "an unavailable node produces an uncertain liveness error without stopping the Server",
       c do
    {:ok, owner} = peer_call(c.peer_a, Jido, :start_agent, [c.jido, RemoteCounter, [id: "owner"]])

    {:ok, server} =
      peer_call(c.peer_b, Jido, :start_agent, [c.jido, RemoteCounter, [id: "server"]])

    :peer.stop(c.peer_a)

    assert {:error, {:liveness_unavailable, ^owner, _}} =
             peer_call(c.peer_b, Server, :attach, [server, owner])

    assert {:error, {:adopt_child_failed, {:liveness_unavailable, ^owner, _}}} =
             peer_call(c.peer_b, Server, :adopt_child, [server, owner, :unavailable])

    parent = Jido.AgentServer.ParentRef.new!(pid: owner, id: "owner", tag: :child)

    assert {:error, {:liveness_unavailable, ^owner, _}} =
             peer_call(c.peer_b, Server, :adopt_parent, [server, parent])

    assert peer_call(c.peer_b, Server, :alive?, [server])
  end

  test "remote admission works in both directions and request forms", c do
    {:ok, older} = peer_call(c.peer_a, Jido, :start_agent, [c.jido, RemoteCounter, [id: "older"]])

    {:ok, younger} =
      peer_call(c.peer_b, Jido, :start_agent, [c.jido, RemoteCounter, [id: "younger"]])

    for {caller, owner, pid} <- [{c.peer_b, c.peer_a, older}, {c.peer_a, c.peer_b, younger}] do
      {:ok, route_signal_1} = RemoteCounter.record_signal(%{value: 1})

      assert {:ok, %{state: %{value: 1}}} =
               peer_call(caller, Jido.AgentServer, :call, [pid, route_signal_1])

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
