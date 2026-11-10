# Sessions and Threads

This guide shows how to record an Agent conversation or work log in a `Jido.Thread`, wrap it in a `Jido.Session`, and store it as a map.

A Thread is an append-only list of entries. A Session owns one Thread and adds a status and its own metadata. Both are immutable values. Neither owns a process or a storage adapter, so you keep them where your code needs them, such as in Agent state or your database.

## Record entries in a Thread

`Jido.Thread.new/1` creates an empty Thread. `Jido.Thread.append/2` takes one entry or a list, and returns the complete next Thread.

```elixir
alias Jido.Thread

thread =
  Thread.new(id: "ticket-42-log", now: 1_000, metadata: %{"queue" => "billing"})
  |> Thread.append([
    %{id: "received", at: 1_001, kind: :customer_message, payload: %{"text" => "Refund INV-7"}},
    %{id: "answered", at: 1_002, kind: "agent.reply", refs: %{"reply_to" => "received"}}
  ])

2 = thread.rev
2 = Thread.entry_count(thread)
[{0, :customer_message}, {1, "agent.reply"}] = Enum.map(Thread.to_list(thread), &{&1.seq, &1.kind})
```

### Entry fields

| Field | Default | Meaning |
| --- | --- | --- |
| `:id` | `"entry_"` and a UUIDv7 | Entry identifier |
| `:seq` | Assigned by the Thread | Position, starting at 0 |
| `:at` | The current system time, in milliseconds | Entry time |
| `:kind` | `:note` | An atom or non-empty string |
| `:payload` | `%{}` | The entry's data |
| `:refs` | `%{}` | Links to other values |

The Thread always assigns `:seq`, and replaces any value you pass. `Jido.Thread.Entry.new/1` builds an entry before you append it.

`:kind` has no fixed list. Each feature defines its own kinds. For example, the AI layer records `:ai_message` entries, as [Thread Projection](../ai/thread-projection.md) describes.

### Read entries

```elixir
alias Jido.Thread

"answered" = Thread.last(thread).id
"received" = Thread.get_entry(thread, 0).id
nil = Thread.get_entry(thread, 99)

[%{id: "received"}] = Thread.filter_by_kind(thread, :customer_message)
[_, _] = Thread.filter_by_kind(thread, [:customer_message, "agent.reply"])
[%{id: "received"}] = Thread.slice(thread, 0, 0)
```

`Jido.Thread.slice/3` uses an inclusive range of sequence numbers. These reads scan the list, so their cost grows with the length of the Thread.

## Wrap a Thread in a Session

`Jido.Session.new/1` creates an open Session with an empty Thread named after it. `Jido.Session.from_thread/2` wraps a Thread you already have.

```elixir
alias Jido.Session

session = Session.new(id: "ticket-42", now: 1_000, metadata: %{"customer" => "acme"})
"ticket-42:thread" = session.thread.id

session =
  Session.append(session, %{id: "received", at: 1_001, kind: :customer_message})

1 = session.rev
1 = session.thread.rev

"session:ticket-42-log" = Session.from_thread(thread).id
```

### Track revisions

A Thread's `:rev` always equals its entry count. A Session's `:rev` counts every Session change, so it can run ahead of the Thread.

```elixir
alias Jido.Session

labelled = Session.put_metadata(session, %{"customer" => "acme", "tier" => "gold"})
2 = labelled.rev
1 = labelled.thread.rev
```

`Jido.Session.put_metadata/2` replaces all of the metadata. An empty append, such as `Jido.Session.append(session, [])`, returns the same Session.

### Close a Session

`Jido.Session.close/1` sets the status to `:closed`. Closing a closed Session returns it unchanged. Appending to a closed Session raises `ArgumentError`. `Jido.Session.put_metadata/2` still works on a closed Session.

```elixir
alias Jido.Session

closed = Session.close(labelled)
false = Session.open?(closed)

"cannot append to a closed session" =
  try do
    Session.append(closed, %{kind: :note})
  rescue
    error in ArgumentError -> Exception.message(error)
  end
```

## Keep payloads portable

Every payload, ref map, and metadata map must pass `Jido.Codec.Term.validate/2`. A PID, function, port, or reference raises `ArgumentError`.

```elixir
alias Jido.Thread

"invalid thread entry" =
  try do
    Thread.append(thread, %{kind: :note, payload: %{"caller" => self()}})
  rescue
    error in ArgumentError -> Exception.message(error)
  end
```

That check allows tuples and structs, which JSON cannot represent. Atom keys and atom values also become strings in a JSON round trip. If you store Sessions as JSON, use string keys and JSON values in payloads, refs, and metadata.

## Store a Session

`Jido.Session.encode/1` returns a versioned map. `Jido.Session.decode/1` validates a map and returns the Session. It accepts maps from JSON, and it checks the internal rules, such as `:rev` and the order of `:seq`.

```elixir
alias Jido.Session

record =
  Session.new(id: "ticket-43", now: 1_000)
  |> Session.append(%{id: "received", at: 1_001, kind: "customer.message", payload: %{"text" => "Hello"}})

document = Session.encode(record)
%{"type" => "jido.session", "version" => 1, "status" => "open"} = document

{:ok, ^record} = document |> JSON.encode!() |> JSON.decode!() |> Session.decode()

{:error, :unsupported_version} = Session.decode(%{"type" => "jido.session", "version" => 2})
{:error, :invalid_session} = Session.decode(Map.put(document, "rev", -1))
```

`Jido.Thread.encode/1` and `Jido.Thread.decode/1` do the same for a Thread. `Jido.Session.decode!/1` raises instead of returning an error.

These maps use a `"version"` field and are not routed by `Jido.Codec`. Call `Jido.Session.encode/1` and `Jido.Session.decode/1` directly. Only version 1 can be read.

### Choose string kinds for stored data

An atom `:kind` encodes as `%{"type" => "atom", "value" => "note"}`. Decoding never creates a new atom. If the atom does not exist on the reading node, decoding fails with `{:error, :invalid_session}`, or `{:error, :invalid_thread}` for a Thread. A string kind has no such dependency, so prefer strings for data that outlives a release.

## Keep a Session in Agent state

`Jido.Session.state_schema/0` returns the schema for a Session field in Agent state. It is the same as `Jido.Session.schema/0`, a closed struct schema.

```elixir
defmodule SessionGuide.SupportDesk do
  use Jido.Agent, name: "support_desk"

  state do
    schema Jido.Joi.object(%{session: Jido.Session.state_schema()})
  end

  routes do
    signal_source "/support/desk"

    route "ticket.note", as: :note do
      action %{text: text},
        schema: Jido.Joi.object(%{text: Jido.Joi.string()}),
        context: context do
        session = Jido.Session.append(context.agent_state.session, %{kind: "ticket.note", payload: %{"text" => text}})
        {:ok, %{context.agent_state | session: session}}
      end
    end
  end
end

{:ok, desk} = SessionGuide.SupportDesk.instantiate(id: "desk-1", state: %{session: Jido.Session.new(id: "ticket-44", now: 1_000)})
{:ok, desk, []} = SessionGuide.SupportDesk.cmd(desk, SessionGuide.SupportDesk.note_signal!(%{text: "Called back"}))

1 = desk.state.session.rev
```

## Related

- [AI Requests and Sessions](../ai/requests-responses-and-sessions.livemd) shows the AI layer's use of Sessions.
- [Thread Projection](../ai/thread-projection.md) turns Thread entries into model messages.
- [Identifiers and UUIDv7](identifiers.md) describes the default IDs.
