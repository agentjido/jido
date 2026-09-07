# Threads and Audit Records

Jido includes two portable values for common history needs. They do not turn an
Agent into an event store, and they do not capture all activity automatically.

## Interaction threads

`Jido.Thread` is an immutable append-only value. An application can keep it in
an Agent schema when entries are part of the Agent state.

```elixir
thread = Jido.Thread.new(metadata: %{conversation_id: "support-42"})

thread =
  Jido.Thread.append(thread, %{
    kind: :message,
    payload: %{role: "user", content: "Where is my order?"}
  })

Jido.Thread.entry_count(thread)
Jido.Thread.last(thread)
Jido.Thread.filter_by_kind(thread, :message)
Jido.Thread.slice(thread, 0, 20)
```

Append returns a new value. It does not commit Agent state. An Action must return
the updated thread as part of the next state.

The application owns:

- the entry kinds and payload formats
- retention and compaction
- the projection sent to a model or external API
- privacy and deletion policy

A list of simple message maps can be sufficient. Use `Jido.Thread` when stable
entry IDs, sequence numbers, timestamps, references, and filtering are useful.

## Domain audit records

`Jido.Plugin.Audit` owns a bounded `:audit` state slice. An Action emits an audit
Directive for a domain fact that must commit with the same Turn.

```elixir
plugins: [{Jido.Plugin.Audit, max_entries: 1_000}]
```

```elixir
directive =
  Jido.Plugin.Audit.record(
    %{event: :order_approved, order_id: "order-42"},
    :ok,
    metadata: %{rule: "manual_review"}
  )
```

The record is portable and becomes part of Agent state. A failed Turn cannot
add it because failed Turns do not commit.

The Plugin does not record every Turn. Select important domain facts in the
Action that owns the decision. Use the Turn outcome at the server error-policy
boundary when an application must record failed Turns elsewhere.

## History is bounded

Both values increase Agent state and checkpoint size. Set an audit limit. Define
a thread retention or summary rule. For large or regulated histories, commit a
stable external record ID in Agent state. Store the full record in an
application-owned system.

Use telemetry for operational events. Use audit records for selected domain
facts. Use threads for ordered interaction content. Each has a different owner
and retention policy.
