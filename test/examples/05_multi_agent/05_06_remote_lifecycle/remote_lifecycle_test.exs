defmodule JidoTest.Examples.MultiAgent.RemoteLifecycleTest do
  use JidoTest.PeerCase

  @moduletag :example
  @moduletag group: :multi_agent

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteLifecycle

  test "node loss reports an unreachable child and does not create a replacement", c do
    assert {:ok, parent} =
             peer_call(c.peer_a, Jido, :start_agent, [
               c.jido,
               RemoteLifecycle,
               [id: "remote-lifecycle-parent"]
             ])

    assert {:ok, _} =
             peer_call(c.peer_a, RemoteLifecycle, :create_worker, [parent, c.node_b])

    child =
      peer_eventually(fn -> peer_call(c.peer_a, Server, :children, [parent])[:worker] end)

    assert node(child.pid) == c.node_b
    assert :ok = :peer.stop(c.peer_b)

    [observation] =
      peer_eventually(fn ->
        case peer_call(c.peer_a, Server, :agent, [parent]).state.observations do
          [] -> nil
          observations -> observations
        end
      end)

    assert observation == %{
             child_id: child.id,
             observation: :unreachable,
             reason: :noconnection
           }

    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert peer_call(c.peer_a, Process, :alive?, [parent])
  end
end
