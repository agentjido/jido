# 04_14 State Migration

A live Agent migrates domain and Plugin-owned state in one validated commit.

## What you will learn

- How a compatible schema supports an idempotent migration through a normal Turn.
- How an explicit definition upgrade validates and persists one complete target state.

## Read the code

Read [the Agent, Plugin, migration Action, and strict definitions](state_migration.ex).
The named migration Action is reused by all three Agent definitions.

## Run it

```sh
mix test test/examples/04_runtime/04_14_state_migration --include example --seed 0
```

Expected result: valid domain and Plugin state migrate once and survive restore.
Invalid target data leaves the old snapshot unchanged.

## Important behavior

The normal Turn path uses a static schema that accepts both formats. The strict
path uses `AgentServer.upgrade/3` to validate and persist a new Agent definition
and its complete state before either becomes visible.

## Limits

The strict upgrade keeps Agent identity and Plugin declarations fixed. It does
not replace Plugin runtime structure or coordinate a multi-node deployment.

## Files

- [Source](state_migration.ex)
- [Tests](../../../test/examples/04_runtime/04_14_state_migration/state_migration_test.exs)

Previous: [Turn Upgrade](../04_13_turn_upgrade/README.md) | Next: [Request Modes](../04_15_request_modes/README.md)
