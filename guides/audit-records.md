# Audit Records

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

## Keep history bounded

Audit records increase Agent state and checkpoint size. Set an audit limit. For
large or regulated histories, commit a stable external record ID in Agent state.
Store the full record in an application-owned system.

Use telemetry for operational events. Use audit records for selected domain
facts. Each has a different owner and retention policy.
