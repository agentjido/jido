# FA-05: Durable deletion

Status: **Core feature required**.

Result on 2026-09-05: **2 passing checks; 1 failing acceptance checks.** All checks are enabled.

## Feature and proof

Existing revisions reject a stale writer. Deletion makes an order unavailable. A delayed initial writer then succeeds with expected_revision 0 and recreates the deleted record.

## Required change

Retain a tombstone and update lifecycle state with compare-and-swap. Reject old writers across deletion and reactivation boundaries.

## Scope

The example uses public persistence APIs and an atomic in-memory byte adapter. It proves loss of revision history after deletion. It does not define tombstone retention or physical purge policy.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_13_durable_delete --include example --seed 0
```

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](durable_delete.ex) · [Tests](../../../../test/examples/99_research/99_13_durable_delete/durable_delete_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
