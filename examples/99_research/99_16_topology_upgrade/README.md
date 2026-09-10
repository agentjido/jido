# 99_16 Topology Upgrade

Status: additive local update implemented; broader rollout remains research.

A Topology Controller adds local Agents while unchanged members keep their PIDs
and state.

## What this proves

- Pure plan comparison identifies added, removed, changed, and unchanged Agents.
- A validated additive update changes later repair without replacing existing members.

## Read the code

Read [the builder, plan comparison, and two worker definitions](topology_upgrade.ex).

## Run it

```sh
mix test test/examples/99_research/99_16_topology_upgrade --include example --seed 0
```

Expected result: three workers grow to five in place, invalid targets have no
effect, and a full Controller replacement restores saved state with new PIDs.

## Gap and limits

Live update accepts additive local Agent entries only. Removal, replacement,
resource changes, ownership transfer, rolling batches, and durable rollout
recovery remain unsupported.

## Files

- [Source](topology_upgrade.ex)
- [Tests](../../../test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs)

Previous: [State Migration](../99_15_state_migration/README.md) | Next: return to [Basic Examples](../../01_basic/README.md)
