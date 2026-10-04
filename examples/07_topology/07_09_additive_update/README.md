# 07_09 Additive Update

A ready Topology Controller adds workers without replacing unchanged Agents.

## What you will learn

- How `Controller.update/3` validates and applies an additive Agent target.
- How unchanged Agents keep their process identity and committed state.

## Read the code

Read [the Topology builder and worker Agent](additive_update.ex), then read the
behavior test.

## Run it

```sh
mix test test/examples/07_topology/07_09_additive_update --include example --seed 0
```

Expected result: three workers grow to five. The first three workers and the
observer keep their PIDs, and committed worker state remains visible. Removal
and a changed worker definition both fail without changing the live Agents.
Controller shutdown removes every Agent.

## Important behavior

The target must keep the same Topology identity, resources, and existing Agent
specifications. Validation completes before the live target changes. The
accepted target becomes the source for later repair passes.

## Limits

Use Controller replacement for removals, changed existing Agent definitions,
resource changes, or an update requested during an active repair pass. This
example does not implement rolling deployment or distributed ownership.

## Files

- [Source](additive_update.ex)
- [Tests](../../../test/examples/07_topology/07_09_additive_update/additive_update_test.exs)

Previous: [Placement Policy](../07_08_placement_policy/README.md) | Next: [Topology Extension](../07_10_topology_extension/README.md)
