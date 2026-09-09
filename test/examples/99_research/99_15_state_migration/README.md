# UP-02: State migration

The baseline has three passing tests and one failure. As of 2026-09-07,
the failing test is temporarily skipped, with its assertion retained.
See the [research test policy](../README.md).

A wallet and its owned audit state migrate in one live commit when the static schema accepts both formats. Invalid target data preserves the whole old snapshot. The migration survives saved-state recovery and an upgrade ID prevents a repeated transformation.

## Required core feature

A strict old schema rejects the new state format. Core needs an explicit operation that installs a target definition with validated, migrated state. Do not relax ordinary Turn validation.

## Run

```sh
mix test test/examples/99_research/99_15_state_migration --include example --seed 0 --trace
```

This is a secondary check. The skipped assertion states desired upgrade
behavior. When the explicit upgrade API exists, connect this example to it
and remove the skip. Current startup and ordinary Turn APIs retain their
existing contracts.

## Scope

The passing path is application state migration with a predeclared schema. It does not replace the definition or a Plugin runtime. Crashes during migration and concurrent upgrade requests remain untested.

[Source](../../../../examples/99_research/99_15_state_migration/state_migration.ex) · [Tests](state_migration_test.exs)
