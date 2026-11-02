defmodule Jido.AI.Contract.ConversationCodecTest do
  use Covenant.Case, component: "jido_ai.conversation", async: true

  alias Jido.AI.Thread.Projection
  alias Jido.{Session, Thread}
  alias Jido.Thread.Entry

  @tag obligation: "jido_ai.conversation.I1"
  test "Entry construction, normalization, and encoding keep the exact portable value" do
    entry =
      Entry.new(
        id: "entry-1",
        seq: 7,
        at: 11,
        kind: :audit,
        payload: %{"value" => 1},
        refs: %{"run_id" => "run-1"}
      )

    assert entry == %Entry{
             id: "entry-1",
             seq: 7,
             at: 11,
             kind: :audit,
             payload: %{"value" => 1},
             refs: %{"run_id" => "run-1"}
           }

    assert Entry.encode(entry) == %{
             "id" => "entry-1",
             "seq" => 7,
             "at" => 11,
             "kind" => %{"type" => "atom", "value" => "audit"},
             "payload" => %{"value" => 1},
             "refs" => %{"run_id" => "run-1"}
           }

    assert {:ok, ^entry} = entry |> Entry.encode() |> Entry.decode()
    assert Entry.normalize(entry, 3, 99) == %{entry | seq: 3}

    string_entry =
      Entry.new(%{
        "id" => "entry-2",
        "seq" => 4,
        "at" => 12,
        "kind" => "custom",
        "payload" => %{"ok" => true},
        "refs" => %{"source" => "test"}
      })

    assert Entry.encode(string_entry)["kind"] == %{"type" => "string", "value" => "custom"}
    assert {:ok, ^string_entry} = string_entry |> Entry.encode() |> Entry.decode()

    normalized =
      entry
      |> Map.merge(%{id: nil, at: nil, kind: nil, payload: nil, refs: nil})
      |> Entry.normalize(8, 99)

    assert normalized.seq == 8
    assert normalized.at == 99
    assert normalized.kind == :note
    assert normalized.payload == %{}
    assert normalized.refs == %{}
    assert String.starts_with?(normalized.id, "entry_")

    assert_raise ArgumentError, "invalid thread entry", fn ->
      Entry.new(id: "", at: 1, kind: :note)
    end
  end

  @tag obligation: "jido_ai.conversation.I1"
  test "Thread construction, append, encoding, and decoding keep exact invariants" do
    thread = Thread.new(id: "thread-1", now: 10, metadata: %{"owner" => "contract"})

    assert thread == %Thread{
             version: 1,
             id: "thread-1",
             rev: 0,
             entries: [],
             created_at: 10,
             updated_at: 10,
             metadata: %{"owner" => "contract"},
             stats: %{entry_count: 0}
           }

    thread =
      Thread.append(thread, [
        Entry.new(id: "entry-1", seq: 20, at: 11, kind: :note, payload: %{value: 1}),
        %{id: "entry-2", at: 12, kind: "audit", payload: %{"value" => 2}, refs: %{r: 2}}
      ])

    assert thread.rev == 2
    assert thread.stats == %{entry_count: 2}
    assert thread.created_at == 10
    assert thread.updated_at >= 10

    assert thread.entries == [
             %Entry{
               id: "entry-1",
               seq: 0,
               at: 11,
               kind: :note,
               payload: %{value: 1},
               refs: %{}
             },
             %Entry{
               id: "entry-2",
               seq: 1,
               at: 12,
               kind: "audit",
               payload: %{"value" => 2},
               refs: %{r: 2}
             }
           ]

    encoded = Thread.encode(thread)

    assert encoded == %{
             "type" => "jido.thread",
             "version" => 1,
             "id" => "thread-1",
             "rev" => 2,
             "entries" => Enum.map(thread.entries, &Entry.encode/1),
             "created_at" => 10,
             "updated_at" => thread.updated_at,
             "metadata" => %{"owner" => "contract"}
           }

    assert {:ok, ^thread} = Thread.decode(encoded)

    without_defaults = encoded |> Map.delete("rev") |> Map.delete("metadata")
    assert {:ok, decoded} = Thread.decode(without_defaults)
    assert decoded.rev == 2
    assert decoded.metadata == %{}
    assert decoded.stats == %{entry_count: 2}

    assert {:error, :invalid_thread} = Thread.validate(%{thread | rev: 1})
    assert {:error, :invalid_thread} = Thread.validate(%{thread | stats: %{entry_count: 1}})
    assert {:error, :invalid_thread} = Thread.validate(%{thread | updated_at: 9})
    assert {:error, :invalid_thread} = Thread.validate(%{thread | entries: tl(thread.entries)})
  end

  @tag obligation: "jido_ai.conversation.I1"
  test "Session construction, encoding, and decoding keep exact ownership values" do
    session = Session.new(id: "session-1", now: 10, metadata: %{"owner" => "contract"})

    assert session == %Session{
             version: 1,
             id: "session-1",
             rev: 0,
             thread: Thread.new(id: "session-1:thread", now: 10),
             status: :open,
             created_at: 10,
             updated_at: 10,
             metadata: %{"owner" => "contract"}
           }

    thread =
      Thread.new(id: "thread-existing", now: 20)
      |> Thread.append(%{id: "entry-existing", kind: :note, at: 21})

    session =
      Session.from_thread(thread,
        id: "session-existing",
        created_at: 19,
        updated_at: thread.updated_at,
        metadata: %{source: "contract"}
      )

    assert session.id == "session-existing"
    assert session.rev == 1
    assert session.thread == thread
    assert session.status == :open
    assert session.created_at == 19
    assert session.updated_at == thread.updated_at
    assert session.metadata == %{source: "contract"}

    encoded = Session.encode(session)

    assert encoded == %{
             "type" => "jido.session",
             "version" => 1,
             "id" => "session-existing",
             "rev" => 1,
             "thread" => Thread.encode(thread),
             "status" => "open",
             "created_at" => 19,
             "updated_at" => thread.updated_at,
             "metadata" => %{source: "contract"}
           }

    assert {:ok, ^session} = Session.decode(encoded)
    assert Session.decode!(encoded) == session

    empty_encoded = Session.new(id: "session-defaults", now: 30) |> Session.encode()
    without_defaults = empty_encoded |> Map.delete("rev") |> Map.delete("metadata")
    assert {:ok, decoded} = Session.decode(without_defaults)
    assert decoded.rev == 0
    assert decoded.metadata == %{}

    assert {:error, :invalid_session} = Session.validate(%{session | version: 2})
    assert {:error, :invalid_session} = Session.validate(%{session | rev: 0})
    assert {:error, :invalid_session} = Session.validate(%{session | updated_at: 18})
  end

  @tag obligation: "jido_ai.conversation.I1"
  test "Session, Thread, and Entry expose complete immutable value operations" do
    assert is_map(Session.schema())
    assert is_map(Session.state_schema())
    assert is_map(Thread.schema())
    assert is_map(Entry.schema())

    thread = Thread.new(id: "codec-thread", now: 10, metadata: %{source: "contract"})
    assert Thread.entry_count(thread) == 0
    assert Thread.last(thread) == nil
    assert Thread.get_entry(thread, 0) == nil
    assert Thread.to_list(thread) == []
    assert Thread.filter_by_kind(nil, :note) == []
    assert Thread.append(thread, nil) == thread
    assert Thread.append(thread, []) == thread

    thread =
      Thread.append(thread, [
        %{kind: :note, payload: %{value: 1}, at: 11},
        %{kind: "audit", payload: %{value: 2}, at: 12}
      ])

    assert Thread.entry_count(thread) == 2
    assert Thread.last(thread).seq == 1
    assert Thread.get_entry(thread, 0).payload == %{value: 1}
    assert Enum.map(Thread.to_list(thread), & &1.seq) == [0, 1]
    assert Enum.map(Thread.filter_by_kind(thread, [:note, "audit"]), & &1.seq) == [0, 1]
    assert Enum.map(Thread.filter_by_kind(thread, :note), & &1.seq) == [0]
    assert Enum.map(Thread.slice(thread, 1, 1), & &1.seq) == [1]
    assert Runic.Identity.Projectable.identity_document(thread) == Thread.encode(thread)

    assert Runic.Identity.Projectable.identity_document(List.first(thread.entries)) ==
             Entry.encode(List.first(thread.entries))

    session =
      Session.from_thread(thread,
        id: "codec-session",
        created_at: 9,
        updated_at: 12,
        metadata: %{owner: "contract"}
      )

    assert Session.open?(session)
    assert Session.append(session, nil) == session
    assert Session.append(session, []) == session

    session = Session.put_metadata(session, %{owner: "updated"})
    assert session.metadata == %{owner: "updated"}
    assert session.rev == 3

    closed = Session.close(session)
    refute Session.open?(closed)
    assert Session.close(closed) == closed

    assert_raise ArgumentError, "cannot append to a closed session", fn ->
      Session.append(closed, %{kind: :note, payload: %{}})
    end

    assert Runic.Identity.Projectable.identity_document(closed) == Session.encode(closed)
  end

  @tag obligation: "jido_ai.conversation.I1"
  test "portable codecs reject unknown versions, fields, shapes, and unsafe values" do
    entry = Entry.new(kind: "custom", payload: %{"ok" => true}, refs: %{"request_id" => "r1"}, at: 1)
    assert {:ok, ^entry} = Entry.decode(entry)
    assert {:ok, %{kind: "custom"}} = entry |> Entry.encode() |> Entry.decode()
    assert {:error, :invalid_entry} = Entry.decode(:invalid)
    assert {:error, :invalid_entry} = Entry.decode(%{"id" => "e", "extra" => true})

    unknown_kind =
      entry
      |> Entry.encode()
      |> Map.put("kind", %{"type" => "atom", "value" => "not_a_loaded_contract_atom"})

    assert {:error, :invalid_entry} = Entry.decode(unknown_kind)
    assert {:error, :invalid_entry} = Entry.validate(:invalid)

    thread = Thread.new(id: "codec-invalid-thread", now: 1) |> Thread.append(entry)
    encoded_thread = Thread.encode(thread)
    assert {:ok, ^thread} = Thread.decode(thread)
    assert {:error, :unsupported_version} = Thread.decode(Map.put(encoded_thread, "version", 2))
    assert {:error, :invalid_thread} = Thread.decode(Map.put(encoded_thread, "entries", %{}))

    assert {:error, :invalid_thread} =
             Thread.decode(Map.put(encoded_thread, "entries", [%{"invalid" => true}]))

    assert {:error, :invalid_thread} = Thread.decode(Map.put(encoded_thread, "extra", true))
    assert {:error, :invalid_thread} = Thread.decode(:invalid)
    assert {:error, :invalid_thread} = Thread.validate(:invalid)
    assert_raise ArgumentError, "invalid thread", fn -> Thread.new(id: "", now: 1) end

    session = Session.from_thread(thread, id: "codec-invalid-session")
    encoded_session = Session.encode(session)
    assert {:ok, ^session} = Session.decode(session)
    assert {:ok, %{status: :open}} = Session.decode(Map.put(encoded_session, "status", :open))
    assert {:ok, %{status: :closed}} = Session.decode(Map.put(encoded_session, "status", :closed))
    assert {:ok, %{status: :closed}} = Session.decode(Map.put(encoded_session, "status", "closed"))
    assert {:error, :unsupported_version} = Session.decode(Map.put(encoded_session, "version", 2))
    assert {:error, :invalid_session} = Session.decode(Map.put(encoded_session, "status", "paused"))
    assert {:error, :invalid_session} = Session.decode(Map.put(encoded_session, "extra", true))
    assert {:error, :invalid_session} = Session.decode(:invalid)
    assert {:error, :invalid_session} = Session.validate(:invalid)

    assert_raise ArgumentError, ~r/invalid session: :unsupported_version/, fn ->
      Session.decode!(Map.put(encoded_session, "version", 2))
    end

    assert_raise ArgumentError, "invalid session metadata", fn ->
      Session.put_metadata(session, %{pid: self()})
    end

    assert_raise ArgumentError, "invalid session", fn ->
      Session.new(id: "", now: 1)
    end
  end

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I3"]
  test "projection rejects invalid sessions and malformed portable messages" do
    session = Session.new(id: "projection-invalid", now: 1)

    assert {:error, :invalid_context} = Projection.context(:invalid, %{})
    assert {:error, :invalid_context} = Projection.context(session, :invalid)
    assert {:error, :invalid_context} = Projection.project(:invalid, %{})
    assert {:error, :invalid_context} = Projection.project(session, :invalid)
    assert {:error, :invalid_context} = Projection.explain(:invalid, %{})
    assert Projection.breakpoint(session) == nil

    assert {:error, :invalid_message} = Projection.append(session, %{role: :unknown, content: "bad"})

    assert {:error, :invalid_message} =
             Projection.append(session, %{role: :assistant, content: "", tool_calls: :invalid})

    assert {:error, :invalid_message} =
             Projection.append(session, %{
               role: :assistant,
               content: "",
               tool_calls: [%{id: "", name: "tool", arguments: %{}}]
             })

    malformed =
      Thread.Entry.new(
        kind: :ai_message,
        payload: %{"version" => 2, "role" => "user", "content" => "bad"},
        at: 2
      )

    malformed_session = Session.append(session, malformed)
    assert {:error, :invalid_context} = Projection.explain(malformed_session, %{})
    assert Projection.breakpoint(malformed_session) == nil
  end

  @tag obligation: ["jido_ai.conversation.I2", "jido_ai.conversation.I5"]
  test "builtin tool calls and simple tool outputs restore to ReqLLM values" do
    session = Session.new(id: "projection-tools", now: 1)
    builtin = ReqLLM.ToolCall.new_builtin("builtin-1", "web_search", Jason.encode!(%{query: "Jido"}))

    {:ok, session} =
      Projection.append(
        session,
        %ReqLLM.Message{role: :assistant, content: [], tool_calls: [builtin]},
        %{},
        2
      )

    {:ok, session} =
      Projection.append(
        session,
        %{role: :tool, name: "web_search", tool_call_id: "builtin-1", content: "found"},
        %{},
        3
      )

    assert Projection.breakpoint(session) == 1
    assert {:ok, %{context: context}} = Projection.context(session)
    [assistant, tool] = ReqLLM.Context.to_list(context)
    assert [call] = assistant.tool_calls
    assert ReqLLM.ToolCall.builtin?(call)
    assert tool.role == :tool
    assert tool.tool_call_id == "builtin-1"
  end
end
