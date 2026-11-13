Code.require_file("session_rollover.ex", __DIR__)

defmodule Jido.Examples.ContextMemory.SessionRolloverTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Examples.ContextMemory.SessionRollover

  test "closes one Session and starts a linked Session with a lossy summary" do
    session =
      Jido.Session.new(id: "session-old", now: 1_000)
      |> Jido.Session.append(%{kind: :note, payload: %{"text" => "full source history"}})

    assert {:ok, result} =
             Jido.Exec.run(SessionRollover, %{
               session: Jido.Session.encode(session),
               expected_rev: session.rev,
               new_session_id: "session-new",
               summary: "The earlier Session established account context."
             })

    archived = Jido.Session.decode!(result.archived_session)
    next = Jido.Session.decode!(result.next_session)

    assert archived.status == :closed
    assert Jido.Thread.entry_count(archived.thread) == 1
    assert next.status == :open
    assert next.metadata["lineage"]["previous_session_id"] == "session-old"
    assert Jido.Thread.last(next.thread).kind == :context_summary
    assert result.replay.complete == false

    assert {:ok, ^archived} =
             result.archived_session |> JSON.encode!() |> JSON.decode!() |> Jido.Session.decode()
  end

  test "rejects a concurrent rollover from a stale revision" do
    session = Jido.Session.new(id: "session-current", now: 1_000)

    assert {:error, %Jido.Error.ValidationError{details: %{expected_rev: 1}}} =
             Jido.Exec.run(SessionRollover, %{
               session: Jido.Session.encode(session),
               expected_rev: 1,
               new_session_id: "session-never-created",
               summary: "stale"
             })
  end
end
