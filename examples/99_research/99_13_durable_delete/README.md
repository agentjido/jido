# FA-05: Durable deletion

Status: **Core feature implemented**.

Result on 2026-09-09: **3 passing checks.** All checks are enabled.

## Feature and proof

Existing revisions reject a stale writer. Deletion writes a compact tombstone
and returns `:deleted` on load. A delayed initial writer conflicts and cannot
recreate the deleted record lifetime.

## Implemented change

Jido retains a tombstone and updates lifecycle state with compare-and-swap. It
rejects old writers across the deletion boundary.

## Scope

The example uses public persistence APIs and an atomic in-memory byte adapter.
It proves retention of the revision fence after deletion. It does not define
tombstone retention or physical purge policy.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_13_durable_delete --include example --seed 0
```

This command returns a passing status.

[Source](durable_delete.ex) · [Tests](../../../test/examples/99_research/99_13_durable_delete/durable_delete_test.exs)
