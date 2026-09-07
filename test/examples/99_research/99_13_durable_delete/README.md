# FA-05: Durable deletion

Status: **Core feature required**.

Baseline on 2026-09-05: 2 passing and 1 failing checks.
As of 2026-09-07, the failing test is temporarily skipped, with reasons.
The original assertions remain. See the [research test policy](../README.md).

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

This is a secondary check. The missing-contract test remains skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_13_durable_delete/durable_delete.ex) · [Tests](durable_delete_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
