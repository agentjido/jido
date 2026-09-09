# FA-05: Durable deletion

Status: **Core feature implemented and proved**.

Baseline on 2026-09-05: 2 passing and 1 failing checks.
As of 2026-09-09, all three checks pass and no check is skipped.

## Feature and proof

Existing revisions reject a stale writer. Deletion makes an order unavailable.
A delayed initial writer cannot replace the durable tombstone.

## Implemented change

Jido retains a tombstone and updates lifecycle state with compare-and-swap. It
rejects old writers across deletion and reactivation boundaries.

## Scope

The example uses public persistence APIs and an atomic in-memory byte adapter.
It proves tombstone fencing after deletion. It does not define tombstone
retention or physical purge policy.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_13_durable_delete --include example --seed 0
```

This is a secondary passing check.

[Source](../../../../examples/99_research/99_13_durable_delete/durable_delete.ex) · [Tests](durable_delete_test.exs)
