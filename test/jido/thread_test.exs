defmodule Jido.ThreadTest do
  use Covenant.Case, component: "jido.thread", async: true

  alias Jido.{Session, Thread}
  alias Jido.Thread.Entry

  @tag obligation: "jido.thread.I1"
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

  @tag obligation: "jido.thread.I1"
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

  @tag obligation: "jido.thread.I1"
  test "stores feature-neutral Agent interactions in append order" do
    thread =
      Thread.new(id: "agent-thread", now: 10, metadata: %{channel: "orders"})
      |> Thread.append([
        %{id: "command", at: 11, kind: :command, payload: %{name: "reserve"}},
        %{id: "result", at: 12, kind: :result, refs: %{command: "command"}}
      ])

    assert thread.rev == 2
    assert Thread.entry_count(thread) == 2

    assert Enum.map(Thread.to_list(thread), &{&1.seq, &1.kind}) == [
             {0, :command},
             {1, :result}
           ]

    assert Thread.last(thread).id == "result"
    assert Thread.get_entry(thread, 0).id == "command"
    assert Enum.map(Thread.filter_by_kind(thread, [:result]), & &1.id) == ["result"]
    assert Enum.map(Thread.slice(thread, 0, 0), & &1.id) == ["command"]
  end

  @tag obligation: "jido.thread.I1"
  test "round-trips portable Thread and Entry values without feature modules" do
    entry =
      Entry.new(
        id: "event",
        seq: 9,
        at: 11,
        kind: "domain.event",
        payload: %{"value" => 3},
        refs: %{"cause" => "command"}
      )

    thread = Thread.new(id: "portable-thread", now: 10) |> Thread.append(entry)

    assert {:ok, ^entry} = entry |> Entry.encode() |> Entry.decode()
    assert {:ok, ^thread} = thread |> Thread.encode() |> Thread.decode()
    assert Runic.Identity.Projectable.identity_document(thread) == Thread.encode(thread)
  end

  @tag obligation: "jido.thread.I2"
  test "rejects process-local data at the Thread value boundary" do
    assert_raise ArgumentError, "invalid thread entry", fn ->
      Entry.new(kind: :command, payload: %{caller: self()})
    end

    assert_raise ArgumentError, "invalid thread", fn ->
      Thread.new(id: "invalid-thread", now: 1, metadata: %{caller: self()})
    end
  end

  @tag obligation: "jido.thread.I1"
  test "preserves the false atom kind through construction, decoding, and append" do
    entry = Entry.new(id: "false-kind", seq: 7, at: 12, kind: false)
    assert entry.kind === false
    assert {:ok, ^entry} = entry |> Entry.encode() |> Entry.decode()

    thread =
      Thread.append(Thread.new(now: 10), [
        %{kind: false, at: 15},
        entry
      ])

    assert Enum.map(Thread.filter_by_kind(thread, false), &{&1.seq, &1.at}) == [{0, 15}, {1, 12}]
    assert {:ok, ^thread} = thread |> Thread.encode() |> Thread.decode()
  end

  @tag obligation: "jido.thread.I2"
  test "rejects false in fields that take typed defaults" do
    entry = Entry.new(kind: :note, at: 1)
    encoded_entry = Entry.encode(entry)
    encoded_thread = Thread.new(now: 1) |> Thread.encode()

    for key <- [:id, :seq, :at, :payload, :refs] do
      assert_raise ArgumentError, "invalid thread entry", fn -> Entry.new([{key, false}]) end
    end

    for key <- ~w(payload refs) do
      bad_entry = Map.put(encoded_entry, key, false)
      assert {:error, :invalid_entry} = Entry.decode(bad_entry)
      assert {:error, :invalid_thread} = Thread.decode(%{encoded_thread | "entries" => [bad_entry], "rev" => 1})
    end

    for key <- ~w(entries rev metadata) do
      assert {:error, :invalid_thread} = Thread.decode(Map.put(encoded_thread, key, false))
    end

    assert_raise ArgumentError, "invalid thread entry", fn ->
      Thread.append(Thread.new(), %{entry | refs: false})
    end
  end

  @tag obligation: "jido.thread.I2"
  test "rejects conflicting Thread and Entry wire keys" do
    thread = Thread.append(Thread.new(now: 1), %{id: "entry", at: 2, payload: %{"id" => 2, id: 1}})
    document = Thread.encode(thread)
    [entry] = document["entries"]
    conflicting_thread = Map.merge(document, %{entries: [], rev: 0})
    conflicting_entry = Map.put(entry, :payload, %{})

    assert {:error, :invalid_thread} = Thread.decode(conflicting_thread)
    assert {:error, :invalid_thread} = Thread.decode(Map.put(document, :version, 2))

    assert {:error, :unsupported_version} =
             Thread.decode(%{"type" => "jido.session", "version" => 1, "thread" => document})

    assert {:error, :invalid_entry} = Entry.decode(conflicting_entry)
    assert {:error, :invalid_thread} = Thread.decode(%{document | "entries" => [conflicting_entry]})

    mixed_entry = entry |> Map.delete("seq") |> Map.put(:seq, 0)
    mixed_thread = document |> Map.delete("entries") |> Map.put(:entries, [mixed_entry])
    assert {:ok, ^thread} = Thread.decode(mixed_thread)

    session = thread |> Session.from_thread() |> Session.encode()
    assert {:error, :invalid_session} = Session.decode(%{session | "thread" => conflicting_thread})
  end

  @tag obligation: "jido.thread.I2"
  test "returns decode errors for improper entry lists and incomplete Thread structs" do
    thread = Thread.new(now: 1) |> Thread.append(%{at: 2})
    [entry] = Thread.to_list(thread)
    document = Thread.encode(thread)
    invalid_document = %{document | "entries" => [Entry.encode(entry) | :tail]}

    assert {:error, :invalid_thread} = Thread.decode(invalid_document)
    assert {:error, :invalid_thread} = Thread.decode(%{thread | entries: [entry | :tail]})
    assert {:error, :invalid_thread} = Thread.decode(%{__struct__: Thread})

    session = thread |> Session.from_thread() |> Session.encode()
    assert {:error, :invalid_session} = Session.decode(%{session | "thread" => invalid_document})
  end

  @tag obligation: "jido.thread.I2"
  test "validates stored entries on append, encode, and decode" do
    thread = Thread.new(now: 1) |> Thread.append(%{at: 2})
    [entry] = Thread.to_list(thread)

    for invalid <- [%{entry | seq: 7}, %{entry | payload: %{caller: self()}}] do
      modified = %{thread | entries: [invalid]}

      assert {:error, :invalid_thread} = Thread.decode(modified)
      assert_raise ArgumentError, "invalid thread", fn -> Thread.encode(modified) end
      assert_raise ArgumentError, "invalid thread", fn -> Thread.append(modified, %{at: 3}) end
    end

    assert_raise ArgumentError, "invalid thread entry", fn -> Entry.encode(%{entry | refs: %{caller: self()}}) end
  end
end
