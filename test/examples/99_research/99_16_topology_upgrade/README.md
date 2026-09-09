# UP-07: Topology upgrade

All five tests pass with no skip.

A pure Agent plan comparison finds additions, removals, changed definitions, and unchanged entries. The second worker definition changes real behavior. Invalid target validation has no live effects. Full controller replacement grows three workers to five and restores saved state, but replaces every PID.

## Implemented core feature

The explicit Controller update operation accepts an additive local Agent
target, retains unchanged members, and changes the repair target.

## Run

```sh
mix test test/examples/99_research/99_16_topology_upgrade --include example --seed 0 --trace
```

This is a secondary check. All assertions are enabled. Current startup and
ordinary Turn APIs retain their existing contracts.

## Scope

The live update adds local Agent entries only. It rejects removal, replacement,
resource changes, and an update during an active pass. It does not handle
ownership transfer, subscriptions, same-module code revisions, rolling batches,
or durable rollout recovery.

[Source](../../../../examples/99_research/99_16_topology_upgrade/topology_upgrade.ex) · [Tests](topology_upgrade_test.exs)
