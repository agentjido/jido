# FA-04: Definition revision checks on restore

Status: **Core feature required**.

Baseline on 2026-09-05: 1 passing and 1 failing checks.
As of 2026-09-07, the failing test is temporarily skipped, with reasons.
The original assertions remain. See the [research test policy](../README.md).

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

This is a secondary check. The missing-contract test remains skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_12_definition_revision/definition_revision.ex) · [Tests](definition_revision_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
