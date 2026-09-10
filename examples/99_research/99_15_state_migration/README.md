# 99_15 State Migration

Status: implemented upgrade contract; awaiting stable upgrade guidance.

A live Agent migrates domain and Plugin-owned state as one validated commit.

## What this proves

- A compatible schema supports an idempotent migration through a normal Turn.
- An explicit upgrade validates complete migrated state against a new definition.

## Read the code

Read [the schemas, Plugin, migration Action, and Agent definitions](state_migration.ex).
The named migration Action is shared by all three definitions.

## Run it

```sh
mix test test/examples/99_research/99_15_state_migration --include example --seed 0
```

Expected result: valid state migrates once and survives restore, while invalid
target data leaves the complete old snapshot unchanged.

## Gap and limits

The strict upgrade keeps Agent identity and Plugin declarations fixed. It does
not replace Plugin runtime structure or coordinate a distributed deployment.

## Files

- [Source](state_migration.ex)
- [Tests](../../../test/examples/99_research/99_15_state_migration/state_migration_test.exs)

Previous: [Turn Upgrade](../99_14_turn_upgrade/README.md) | Next: [Topology Upgrade](../99_16_topology_upgrade/README.md)
