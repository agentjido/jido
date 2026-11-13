Code.require_file("request_report.ex", __DIR__)
Code.require_file("saved_agent.ex", __DIR__)
Code.require_file("../support/durable_peer.exs", __DIR__)

defmodule Jido.Examples.Durable.SavedAgentTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  @moduletag :peer
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.SavedAgent, as: Example
  alias Jido.Test.Examples.Durable.Peer

  @instance Jido.DurableSavedAgentExample
  @sources Path.wildcard(Path.expand("*.ex", __DIR__))

  test "a confirmed request restores unchanged after SIGKILL of the entire BEAM", c do
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("saved-report")
    {writer, writer_node} = start_beam()
    server = start_agent(writer, id, persistence, :create)
    assert {:ok, request} = Example.request_signal(%{report_id: "report-42", topic: "  OTP  "})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             :peer.call(writer, Server, :call, [server, request])

    snapshot = :peer.call(writer, Server, :snapshot, [server])
    accepted = snapshot.agent
    assert snapshot.agent_revision == 1
    assert accepted.state == %{report_id: "report-42", topic: "OTP", status: :requested}

    # A rejected Turn cannot replace the last confirmed request.
    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             :peer.call(writer, Server, :call, [
               server,
               %{request | data: %{report_id: "invalid", topic: "   "}}
             ])

    failed_snapshot = :peer.call(writer, Server, :snapshot, [server])
    assert failed_snapshot.agent == accepted
    assert failed_snapshot.agent_revision == 1

    Peer.kill(writer)
    {reader, reader_node} = start_beam()
    assert reader_node != writer_node
    restored = start_agent(reader, id, persistence, :restore)
    restored_snapshot = :peer.call(reader, Server, :snapshot, [restored])
    assert restored_snapshot.agent == failed_snapshot.agent
    assert restored_snapshot.agent_revision == failed_snapshot.agent_revision

    # Restore preserves the domain guard, but adds no command receipt protocol.
    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed}} =
             :peer.call(reader, Server, :call, [restored, request])

    final_snapshot = :peer.call(reader, Server, :snapshot, [restored])
    assert final_snapshot.agent == accepted
    assert final_snapshot.agent_revision == 1

    assert :ok = :peer.call(reader, Jido, :stop_agent, [@instance, restored])
    assert :peer.call(reader, Jido, :resident_agent_count, [@instance]) == 0
    Peer.stop(reader)
  end

  test "restore requires an existing record and never creates fresh state", c do
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = unique_id("missing-report")

    # A fast failure can return its reason from the start call itself.
    assert {:error, :not_found} =
             with(
               {:ok, server} <- Jido.thaw(c.jido, Example, id, persistence: persistence),
               do: Server.await_ready(server)
             )

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
