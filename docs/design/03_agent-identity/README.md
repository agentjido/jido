> Deferred design proposal. This document is pending approval. It does not
> define the current core API.

# 03 — Stable Agent identity

Current comparison: [gap analysis](gap-analysis.md).

Stable Agent identity defines who an Agent is across processes, nodes,
restarts, storage, and transport. It does not decide where the Agent runs or
which activation has write authority.

The proposed identity is:

```elixir
%Jido.Agent.Ref{
  namespace: "my-app/primary",
  partition: nil,
  id: "order-123"
}
```

The identity tuple is `{namespace, partition, id}`. Namespace and ID are
nonempty strings. Partition is nil or a nonempty string. The Agent module and
definition revision belong in its checkpoint. They are not process identity.

The same Ref is used by:

- Local Registry lookup.
- Persistence Records.
- Agent-to-Agent Signal Directives.
- Explicit remote placement.
- Future cluster directories and transport gateways.

A PID is a local runtime handle. It is not durable Agent identity. Dispatch
resolves the current runtime location from the Ref for each delivery.

Cluster operation has three separate questions:

```text
Stable Agent identity
  Who is this Agent?

Cluster location
  Where is it running now?

Durable authority
  Which activation can commit?
```

`Jido.Agent.Ref` answers only the first question. A cluster directory can
answer the second. A storage claim, lease, or fencing service must answer the
third when split-brain protection is required.

Main alignment questions:

- Is stable namespace identity required for the V3 core release?
- Does the current Jido module name remain part of durable storage identity?
- Can one Ref move between Erlang nodes without changing identity?
- Which operations resolve only local location, and which can use transport?
- How are stale cached locations detected?
- Which package owns cluster location and durable activation authority?
