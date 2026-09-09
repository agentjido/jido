# UP-02: State migration

All four tests pass.

A wallet and its owned audit state migrate in one live commit when the static schema accepts both formats. Invalid target data preserves the whole old snapshot. The migration survives saved-state recovery and an upgrade ID prevents a repeated transformation.

## Implemented core feature

A strict old schema rejects the new state format. The explicit Agent Server
upgrade operation installs a target definition only after the target validates
the complete migrated state. Ordinary Turn validation stays unchanged.

## Run

```sh
mix test test/examples/99_research/99_15_state_migration --include example --seed 0 --trace
```

All assertions are enabled. Current startup and ordinary Turn APIs retain their
existing contracts.

## Scope

The compatible path remains an application migration with a predeclared
schema. The strict path replaces the Agent definition but keeps the same Agent
identity and Plugin declarations. It does not replace Plugin runtime structure.

[Source](state_migration.ex) · [Tests](../../../test/examples/99_research/99_15_state_migration/state_migration_test.exs)
