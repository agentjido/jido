# 10_04 Nested Agents

An Agent owns a team whose Agent definition declares two workers.

## What you will learn

- How an Agent definition can contain another Agent definition.
- How each nested Agent owns its declared member runtimes.
- How one failed worker restarts without replacing its sibling.
- Why a root snapshot contains topology intent but not current member state.
- How stopping the root stops its complete static subtree.

## Read the code

Read the root Agent, then `Hierarchy.Team` in the same file, then the Cell Agent and tests.

## Run it

```sh
mix test.examples examples/10_declared_agent_topologies/10_04_nested_agents
```

Expected result: The root, team, and two workers start. Workers keep separate
state. One failed worker restarts in isolation. Stopping the root stops the
complete team subtree.

## Important behavior

Containment comes from nested Agent declarations. There is no separate
`owns` graph or Controller. The definition stays fixed for the activation.

## Limits

Root removal is intentional and does not leave a detached team. The public API
does not remove one selected declared subtree while the root stays active. A
saved root contains topology intent, not one coordinated child checkpoint.
This example does not define remote placement or member-state recovery.

## Files

- [Source](hierarchy.ex)
- [Cell Agent](../support/cell.ex)
- [Tests](hierarchy_test.exs)
- [Public runtime support](../support/runtime.ex)

This is also the Agent hierarchy lesson. Nested definitions replace the old
recursive spawn example; subtree ownership follows the OTP supervisor tree.

Previous: [Local Bus Broadcast](../10_03_bus_broadcast/README.md) | Next: [Plugins](../../05_plugins/README.md)
