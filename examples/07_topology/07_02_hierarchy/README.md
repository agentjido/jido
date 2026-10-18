# 07_02 Nested Agents

An Agent owns a team whose Agent definition declares two workers.

## What you will learn

- How an Agent definition can contain another Agent definition.
- How each nested Agent owns its declared member runtimes.
- How `agent_remove` removes a nested owner and its complete subtree.

## Read the code

Read the root Agent, then `Hierarchy.Team` in the same file, then the Cell Agent and tests.

## Run it

```sh
mix test test/examples/07_topology/07_02_hierarchy --include example --seed 0
```

Expected result: The root, team, and two workers start. Workers keep separate state.
Removing the team leaves the root running and stops the complete team subtree.

## Important behavior

Containment comes from nested Agent declarations. There is no separate
`owns` graph or Controller. The remove Action returns a data mutation.
AgentServer validates and commits it, then reconciles the runtime.
Wait for `Server.await_ready(server)` after the mutation.

## Limits

Removal is intentional and does not leave a detached team. This example
does not define remote placement, orphan adoption, or member-state recovery.

## Files

- [Source](hierarchy.ex)
- [Cell Agent](../support/cell.ex)
- [Tests](../../../test/examples/07_topology/07_02_hierarchy/hierarchy_test.exs)
- [Test runtime assertions](../../../test/examples/support/agent_topology_assertions.ex)

Previous: [Named Members](../07_01_independent/README.md) | Next: [Local Bus Broadcast](../07_03_bus_swarm/README.md)

This is also the Agent hierarchy lesson. Nested definitions replace the old
recursive spawn example; subtree ownership follows the OTP supervisor tree.
