defmodule Jido.SessionTest do
  use Covenant.Case, component: "jido_ai.conversation", async: true

  alias Jido.{Agent, Session, Thread}
  alias Jido.Test.AI.SimpleAgent

  @tag obligation: "jido_ai.conversation.I1"
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

  @tag obligation: "jido_ai.conversation.I1"
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

  @tag obligation: "jido_ai.conversation.I1"
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

  @tag obligation: "jido_ai.conversation.I1"
  test "constructors keep their identity and time defaults" do
    %Session{id: "session_" <> suffix} = created = Session.new(now: 10)
    assert Jido.Id.uuid7?(suffix)
    assert created.thread.id == created.id <> ":thread"

    thread =
      Thread.new(id: "existing", now: 5)
      |> Thread.append(%{id: "event", kind: :note, at: 6})

    assert %Session{id: "explicit", thread: ^thread, rev: 1, created_at: 10, updated_at: 10} =
             Session.new(id: "explicit", now: 10, thread: thread)

    assert %Session{id: "session:existing", thread: ^thread, rev: 1, created_at: 5} =
             wrapped = Session.from_thread(thread)

    assert wrapped.updated_at == thread.updated_at
  end

  @tag obligation: "jido_ai.conversation.I6"
  test "Agent state enforces portable Session and Thread invariants" do
    session = Session.new(id: "session", now: 10)
    closed = Session.close(session)
    assert {:ok, agent} = SimpleAgent.instantiate(id: "agent")
    assert agent.state.session == nil
    assert {:ok, %{state: %{session: ^closed}}} = Agent.set(agent, session: closed)
    assert {:ok, %{state: %{session: ^session}}} = SimpleAgent.instantiate(id: "agent", state: %{session: session})

    with_entry = Session.append(session, %{id: "entry", kind: :note, at: 11})

    for invalid <- [
          %{session | version: 2},
          %{with_entry | rev: 0},
          %{session | updated_at: 9},
          %{session | metadata: %{pid: self()}},
          %{with_entry | thread: %{with_entry.thread | stats: %{entry_count: 0}}}
        ] do
      assert {:error, :invalid_session} = Session.decode(invalid)

      assert {:error, %Jido.Error.ValidationError{code: :invalid_state}} =
               SimpleAgent.instantiate(id: "agent", state: %{session: invalid})

      assert {:error, %Jido.Error.ValidationError{code: :invalid_state}} = Agent.set(agent, session: invalid)
    end
  end

  @tag obligation: "jido_ai.conversation.I6"
  test "version 1 accepts both field key forms and equal duplicates" do
    session = Session.new(id: "session", now: 10)
    document = Session.encode(session)
    atom_keys = Map.new(document, fn {key, value} -> {String.to_existing_atom(key), value} end)
    mixed_keys = document |> Map.delete("id") |> Map.put(:id, session.id)

    for input <- [
          document,
          atom_keys,
          mixed_keys,
          Map.put(document, :id, session.id),
          Map.drop(document, ["rev", "metadata"]),
          Map.merge(document, %{"rev" => nil, "metadata" => nil})
        ] do
      assert {:ok, ^session} = Session.decode(input)
    end
  end

  @tag obligation: "jido_ai.conversation.I6"
  test "version 1 rejects conflicting keys, false defaults, and document struct markers" do
    document = Session.encode(Session.new(id: "session", now: 10))

    for input <- [
          Map.put(document, :id, "different"),
          Map.put(document, :version, 2),
          Map.put(document, "rev", false),
          Map.put(document, "metadata", false),
          Map.put(document, "__struct__", "Other"),
          Map.put(document, :__struct__, Thread)
        ] do
      assert {:error, :invalid_session} = Session.decode(input)
    end
  end

  @tag obligation: "jido_ai.conversation.I6"
  test "decode returns tagged errors for malformed Threads and unsupported versions" do
    session =
      Session.new(id: "session", now: 10)
      |> Session.append(%{id: "entry", kind: :note, at: 11})

    document = Session.encode(session)
    [encoded] = document["thread"]["entries"]
    [entry] = session.thread.entries

    for malformed <- [
          put_in(document, ["thread", "entries"], [encoded | :invalid]),
          put_in(session.thread.entries, [entry | :invalid]),
          %{session | thread: Map.delete(session.thread, :entries)}
        ] do
      assert {:error, :invalid_session} = Session.decode(malformed)
      assert_raise ArgumentError, "invalid session: :invalid_session", fn -> Session.decode!(malformed) end
    end

    for unsupported <- [
          Map.merge(document, %{"version" => 2, "new_field" => true}),
          put_in(document, ["thread", "version"], 2)
        ] do
      assert {:error, :unsupported_version} = Session.decode(unsupported)
      assert_raise ArgumentError, "invalid session: :unsupported_version", fn -> Session.decode!(unsupported) end
    end
  end
end
