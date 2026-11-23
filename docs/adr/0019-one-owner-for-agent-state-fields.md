# ADR 0019 One owner for each Agent state field

- Status: Accepted
- Date: 2026-11-22

## Context

The first Counter spike saved the proposal in `after_commit/3`. A SQLite
conflict test showed that Jido could report a committed Turn even when Ecto
rejected the write. An external writer can change the row after admission.

## Decision

Give each Agent state field one authoritative owner. Ordinary Agent state
belongs to Jido. The built-in Plugin uses `ecto CounterState` to declare that
Ecto owns the Agent's domain fields. The Agent uses a row snapshot for a Turn.
On the next Turn or after recovery, read those fields from the row. Any copy
in Agent state or a checkpoint is derived. Agent authoring rejects a Joi
schema or initial state in the same declaration.

Fetch the current Ecto row through the state-read API. A Jido snapshot
pairs the committed Agent value with its Jido revisions. External row changes
can occur independently of those revisions.

Read the row version with its values. Save a proposal only if the version
still matches. If the version changed, keep the newer row. A caller who
requires confirmation of the row update must receive success only after the
version-checked write succeeds.

## Consequences

With Jido persistence enabled, `before_commit/3` can reject the proposed
state before the terminal checkpoint. The Ecto Plugin rejects write
proposals in this setup. With Jido persistence disabled, the Plugin saves
the proposal against the admitted row version before Jido reports success.
A stale write fails the Turn. An optional ledger uses `after_commit/3`.

If a durable Jido checkpoint or Turn receipt must commit atomically with the
row, the persistence boundary must save both in one transaction.

## References

- [Ecto Counter and conflict test](../../test/jido/agent_server/ecto_state_test.exs)
- [Plugin callback contract](../../lib/jido/plugin.ex)
- [Ecto state spike plan](../plans/2026-11-21-2106-ecto-agent-state-plan.md)
