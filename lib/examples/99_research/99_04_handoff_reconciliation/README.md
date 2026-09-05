# FA-08: Acknowledged handoff and worker reconciliation

Status: **Works as an application protocol**.

Result on 2026-09-05: **3 passing checks; 0 failing acceptance checks.** All checks are enabled.

## Feature and proof

Real child Agents acknowledge transfer. The coordinator rejects stale and duplicate results. An unavailable recipient leaves the old owner. Recipient loss clears the pending offer, and explicit reconciliation starts a replacement with a new generation. Parent shutdown removes children.

## Required change

No core feature is required for this proof. Keep request authority, acknowledgements, generations, and desired worker policy in application state.

## Scope

There is one request and one live coordinator. The tests cover recipient loss, not durable coordinator loss or arbitrary network partitions. The coordinator controls accepted results; external effects require their own fencing.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_04_handoff_reconciliation --include example --seed 0
```

This command passes with the current core. The extension policy is part of the example.

[Source](handoff.ex) · [Tests](../../../../test/examples/99_research/99_04_handoff_reconciliation/handoff_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
