> Subsystem review index. This document is pending approval.

# 07 — Persistence

Current comparison: [gap analysis](gap-analysis.md).

Persistence owns checkpoint storage, record identity, compare-and-swap,
restore, durable lifecycle state, deletion, and write-authority failure rules.

Review [the instance persistence proposal](instance-persistence.md) against
`lib/jido/persistence.ex`, `lib/jido/persistence/adapter.ex`, and the current
ETS, File, and Redis adapters.

[The adapter and durable lifecycle design](persistence-adapters.md) refines the
byte-store boundary. It proposes `get/2` and `compare_and_swap/4` as the minimum
adapter contract, durable tombstones for deletion, a revision-zero write before
readiness, optional Ecto and Bedrock adapters, and host-owned storage processes.

Main alignment questions:

- Does core keep the binary Adapter contract or add instance callbacks?
- What are the public Checkpoint, Commit, and Record values?
- When is the initial persistent Agent written and published?
- Does every write error remove Server write authority?
- Does normal deletion write a tombstone?
- Which migration work belongs to core, a Plugin, or a durable package?
