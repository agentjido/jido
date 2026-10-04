# 05_04 Remote Child

A parent Agent places an owned child on a selected connected Erlang node and
receives its result through normal Jido Signals.

## What you will learn

- How `SpawnChild` expresses explicit remote placement.
- How parent ownership and result delivery work across nodes.

## Read the code

Read [the parent Agent](remote_child.ex), then [the remote counter](remote_counter.ex),
[the behavior test](../../../test/examples/05_multi_agent/05_04_remote_child/remote_child_test.exs),
and the optional [two-node demonstration](demo.exs).

## Run it

```sh
mix test test/examples/05_multi_agent/05_04_remote_child --include example --seed 0
```

Expected result: the child runs on the requested node, returns its execution
node and value, and stops when the parent requests cleanup.

## Important behavior

The parent keeps ownership metadata on its node. The child is registered and
supervised on the selected node. Result delivery still uses a child-to-parent
Directive.

A timeout or node disconnect during a remote start does not prove that the
child did not start. Keep the tag unresolved. Retry only the same `SpawnChild`
request with the same target and options. Use `AgentServer.status/1` to inspect
`pending_child_spawns`, then use `AgentServer.children/1` and the target Agent
identity to reconcile the result. Do not reuse the tag while the result is
unknown.

## Limits

The nodes must already be connected and run compatible code. Placement does
not establish cluster-wide exclusive ownership. Core has no public operation
that cancels a pending remote start.

## Files

- [Parent Agent](remote_child.ex)
- [Child Agent](remote_counter.ex)
- [Tests](../../../test/examples/05_multi_agent/05_04_remote_child/remote_child_test.exs)
- [Demonstration](demo.exs)

Previous: [Agent Hierarchy](../05_03_agent_hierarchy/README.md) | Next: [Remote Lifecycle](../05_05_remote_lifecycle/README.md)
