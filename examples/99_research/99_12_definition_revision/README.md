# FA-04: Definition revision checks on restore

Status: **Core feature required**.

Result on 2026-09-05: **1 passing checks; 1 failing acceptance checks.** All checks are enabled.

## Feature and proof

A matching cart definition restores total 20. After the same module changes from revision 1 to revision 2, restore still succeeds and returns metadata for revision 2.

## Required change

Save and enforce a positive module-owned definition revision. Reject a mismatch before restoration, even when saved state still passes its schema.

## Scope

Core has no definition_revision option. The probe declares the intended revision in module metadata and a function. It recompiles only its isolated Cart module in a serial test. It does not implement automatic state migration.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_12_definition_revision --include example --seed 0
```

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](definition_revision.ex) · [Tests](../../../test/examples/99_research/99_12_definition_revision/definition_revision_test.exs) · [Complete result log](../../../docs/examples/feature-acceptance-results.md)
