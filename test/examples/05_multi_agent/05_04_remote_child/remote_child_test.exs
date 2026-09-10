defmodule JidoTest.Examples.MultiAgent.RemoteChildTest do
  use JidoTest.PeerCase

  @moduletag :example
  @moduletag group: :multi_agent

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteParent

  test "a parent runs one requested child on a known node and receives its result", c do
    assert {:ok, parent} =
             peer_call(c.peer_a, Jido, :start_agent, [c.jido, RemoteParent, [id: "remote-parent"]])

    assert {:ok, _} = peer_call(c.peer_a, RemoteParent, :request_child, [parent, c.node_b])

    child = peer_call(c.peer_a, Server, :children, [parent], 5_000)[:worker]

    assert node(child.pid) == c.node_b
    assert peer_call(c.peer_b, Process, :alive?, [child.pid])

    assert {:ok, _} =
             peer_call(c.peer_a, RemoteParent, :request_result, [parent, 21, "request-1"])

    result =
      peer_eventually(
        fn ->
          case safe_peer_call(c.peer_a, Server, :agent, [parent]) do
            %{state: %{result: result}} when map_size(result) > 0 -> result
            _not_ready -> nil
          end
        end,
        timeout: 3_000
      )

    assert result == %{executed_on: c.node_b, request_id: "request-1", value: 21}
    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])

    peer_eventually(
      fn -> not peer_call(c.peer_b, Process, :alive?, [child.pid]) end,
      timeout: 2_000
    )
  end

  defp safe_peer_call(peer, module, function, args) do
    peer_call(peer, module, function, args, 1_000)
  catch
    :exit, _reason -> nil
  end
end
