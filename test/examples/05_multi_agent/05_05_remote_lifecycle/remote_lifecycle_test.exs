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

    child = peer_call(c.peer_a, Server, :children, [parent], 5_000)[:worker]

    assert node(child.pid) == c.node_b
    assert :ok = :peer.stop(c.peer_b)

    [observation] =
      peer_eventually(
        fn ->
          case safe_peer_call(c.peer_a, Server, :agent, [parent]) do
            %{state: %{observations: []}} -> nil
            %{state: %{observations: observations}} -> observations
            _not_ready -> nil
          end
        end,
        timeout: 3_000
      )

    assert observation == %{
             child_id: child.id,
             observation: :unreachable,
             reason: :noconnection
           }

    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert peer_call(c.peer_a, Process, :alive?, [parent])
  end

  defp safe_peer_call(peer, module, function, args) do
    peer_call(peer, module, function, args, 1_000)
  catch
    :exit, _reason -> nil
  end
end
