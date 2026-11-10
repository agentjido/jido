defmodule Jido.SessionTest do
  use ExUnit.Case, async: true

  alias Jido.{Session, Thread}

  test "owns one Agent Thread without an AI or runtime owner" do
    session = Session.new(id: "agent-session", now: 10, metadata: %{purpose: "orders"})

    assert session.id == "agent-session"
    assert session.thread.id == "agent-session:thread"
    assert session.rev == 0
    assert Session.open?(session)

    next =
      Session.append(session, %{
        id: "command",
        at: 11,
        kind: :command,
        payload: %{name: "reserve"}
      })

    assert next.rev == 1
    assert next.thread.rev == 1
    assert next.thread.entries |> List.first() |> Map.fetch!(:kind) == :command
  end

  test "builds from an existing Thread and keeps lifecycle immutable" do
    thread =
      Thread.new(id: "existing-thread", now: 10)
      |> Thread.append(%{id: "entry", at: 11, kind: :observation})

    session = Session.from_thread(thread, id: "existing-session", created_at: 9)
    changed = Session.put_metadata(session, %{owner: "application"})
    closed = Session.close(changed)

    assert session.thread == thread
    assert changed.metadata == %{owner: "application"}
    assert changed.rev == session.rev + 1
    refute Session.open?(closed)
    assert Session.close(closed) == closed

    assert_raise ArgumentError, "cannot append to a closed session", fn ->
      Session.append(closed, %{kind: :command})
    end
  end

  test "round-trips a portable Session without runtime state" do
    session =
      Session.new(id: "portable-session", now: 10)
      |> Session.append(%{id: "event", at: 11, kind: "domain.event"})

    assert {:ok, ^session} = session |> Session.encode() |> Session.decode()
    assert Session.decode!(Session.encode(session)) == session
    assert Runic.Identity.Projectable.identity_document(session) == Session.encode(session)

    assert_raise ArgumentError, "invalid session metadata", fn ->
      Session.put_metadata(session, %{caller: self()})
    end
  end
end
