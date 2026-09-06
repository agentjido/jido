# UP-02: State migration

Three tests pass. One enabled test fails.

A wallet and its owned audit state migrate in one live commit when the static schema accepts both formats. Invalid target data preserves the whole old snapshot. The migration survives saved-state recovery and an upgrade ID prevents a repeated transformation.

## Required core feature

A strict old schema rejects the new state format. Core needs an explicit operation that installs a target definition with validated, migrated state. Do not relax ordinary Turn validation.

## Run

```sh
mix test test/examples/99_research/99_15_state_migration --include example --seed 0 --trace
```

The failed assertion is enabled and states desired upgrade behavior. When the
explicit upgrade API exists, connect this example to it. Current startup and
ordinary Turn APIs retain their existing contracts.

## Scope

The passing path is application state migration with a predeclared schema. It does not replace the definition or a Plugin runtime. Crashes during migration and concurrent upgrade requests remain untested.

[Source](state_migration.ex) · [Tests](../../../test/examples/99_research/99_15_state_migration/state_migration_test.exs)

[All ten upgrade cases and results](../../../docs/examples/live-upgrade-results.md)
