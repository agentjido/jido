defmodule JidoTest.Examples.Durable.SavedAgentTest do
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag :peer
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.SavedAgent, as: Example
  alias JidoTest.Examples.Durable.Peer

  @instance Jido.DurableSavedAgentExample
  @sources Path.wildcard(
             Path.expand("../../../../examples/11_durable/11_01_saved_agent/*.ex", __DIR__)
           )

  test "a confirmed request restores unchanged after SIGKILL of the entire BEAM", c do
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("saved-report")
    {writer, writer_node} = start_beam()
    server = start_agent(writer, id, persistence, :create)
    assert {:ok, request} = Example.request_signal(%{report_id: "report-42", topic: "  OTP  "})
    assert {:ok, accepted, []} = :peer.call(writer, Server, :call, [server, request])
    snapshot = :peer.call(writer, Server, :snapshot, [server])
    assert snapshot == %{agent: accepted, state_version: 2}
    assert accepted.state == %{report_id: "report-42", topic: "OTP", status: :requested}

    # A rejected Turn cannot replace the last confirmed request.
    assert {:error, _} =
             :peer.call(writer, Server, :call, [
               server,
               %{request | data: %{report_id: "invalid", topic: "   "}}
             ])

    failed_snapshot = :peer.call(writer, Server, :snapshot, [server])
    assert failed_snapshot == %{agent: accepted, state_version: 4}

    Peer.kill(writer)
    {reader, reader_node} = start_beam()
    assert reader_node != writer_node
    restored = start_agent(reader, id, persistence, :restore)
    assert :peer.call(reader, Server, :snapshot, [restored]) == failed_snapshot

    # Restore preserves the domain guard, but adds no command receipt protocol.
    assert {:error, _} = :peer.call(reader, Server, :call, [restored, request])

    assert :peer.call(reader, Server, :snapshot, [restored]) ==
             %{agent: accepted, state_version: 6}

    assert :ok = :peer.call(reader, Jido, :stop_agent, [@instance, restored])
    assert :peer.call(reader, Jido, :agent_count, [@instance]) == 0
    Peer.stop(reader)
  end

  test "restore requires an existing record and never creates fresh state", c do
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("missing-report")
    assert {:ok, server} = Jido.thaw(c.jido, Example, id, persistence: persistence)
    assert {{:shutdown, :not_found}, _} = catch_exit(Server.await_ready(server))
    assert Jido.whereis_agent(c.jido, id) == nil
  end

  defp start_beam do
    {peer, peer_node} = Peer.start(@sources)

    # The application supervisor owns the instance, not the temporary RPC caller.
    assert {:ok, _} =
             :peer.call(peer, Supervisor, :start_child, [
               Jido.Supervisor,
               {Jido, name: @instance, namespace: "examples/durable/saved_agent"}
             ])

    {peer, peer_node}
  end

  defp start_agent(peer, id, persistence, mode) do
    assert {:ok, server} =
             :peer.call(peer, Jido, :start_agent, [
               @instance,
               Example,
               [id: id, persistence: persistence, persistence_mode: mode]
             ])

    assert :ok = :peer.call(peer, Server, :await_ready, [server])
    server
  end
end
