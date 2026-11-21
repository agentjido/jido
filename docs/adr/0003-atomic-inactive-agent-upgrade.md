# ADR 0003: Upgrade an inactive saved Agent atomically

- Status: Accepted
- Date: 2026-11-03

## Context

Snapshot restore rejects changed or unavailable executable references. The snapshot upgrade function can convert old data, but a caller could not apply it directly to an inactive durable Agent. Starting the old Agent first is not safe when its code has changed.

## Decision

Use `Jido.Persistence.upgrade_agent/5` to upgrade one inactive saved Agent.

The operation reads and validates one active record. It runs the explicit upgrade Action on the saved snapshot before it resolves old code references. It validates the result, builds the next complete record, and writes the next revision with compare-and-swap.

The operation refuses a record with a nonterminal durable Turn. It keeps a terminal Turn receipt. It does not expose Persistence record data as a public value.

## Consequences

- An application can deploy new code, upgrade saved Agents, and then activate them.
- A concurrent writer causes a conflict and does not overwrite newer data.
- Failed validation or upgrade work does not change stored bytes.
- An application must first settle or cancel a nonterminal durable Turn.

## References

- `Jido.Persistence.upgrade/3`
- `Jido.Persistence.upgrade_agent/5`
- Covenant obligation `jido.persistence.I16`
