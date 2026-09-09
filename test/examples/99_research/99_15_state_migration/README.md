# UP-02: State migration

All four tests pass with no skip.

A wallet and its owned audit state migrate in one live commit when the static schema accepts both formats. Invalid target data preserves the whole old snapshot. The migration survives saved-state recovery and an upgrade ID prevents a repeated transformation.

## Implemented core feature

A strict old schema rejects the new state format. The explicit Agent Server
upgrade operation validates migrated complete state against the target
definition before commit. Ordinary Turn validation stays unchanged.

## Run

```sh
mix test test/examples/99_research/99_15_state_migration --include example --seed 0 --trace
```

This is a secondary check. All assertions are enabled. Current startup and
ordinary Turn APIs retain their existing contracts.

## Scope

The compatible path remains an application migration with a predeclared
schema. The strict path replaces the Agent definition while the identity and
Plugin declarations stay fixed. It does not replace Plugin runtime structure.

[Source](../../../../examples/99_research/99_15_state_migration/state_migration.ex) · [Tests](state_migration_test.exs)
