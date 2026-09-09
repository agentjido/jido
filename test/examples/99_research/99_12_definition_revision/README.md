# FA-04: Definition revision checks on restore

Status: **Core feature implemented and proved**.

Baseline on 2026-09-05: 1 passing and 1 failing checks.
As of 2026-09-09, both checks pass and no check is skipped.

## Feature and proof

A matching cart definition restores total 20. After the same module changes
from revision 1 to revision 2, restore rejects the checkpoint with the
`definition_mismatch` code.

## Implemented change

Jido saves and enforces a positive module-owned definition revision. It rejects
a mismatch before restoration, even when saved state still passes its schema.

## Scope

The probe recompiles only its isolated Cart module in a serial test. It does
not implement automatic state migration or pin loaded Action code for a live
Turn.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_12_definition_revision --include example --seed 0
```

This is a secondary passing check.

[Source](../../../../examples/99_research/99_12_definition_revision/definition_revision.ex) · [Tests](definition_revision_test.exs)
