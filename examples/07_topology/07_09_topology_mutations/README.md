# 07_09 Topology Mutations

Agent mutation directives add, resize, replace, and remove live members.

## What you will learn

- How Actions return `agent_add`, `agent_update`, `agent_replace`, and `agent_remove`.
- How unchanged members keep their processes and committed state.
- How an invalid mutation preserves the accepted Agent and revision.

## Read the code

Read the mutation routes and initial observer declaration, then the Cell Agent and tests.

## Run it

```sh
mix test test/examples/07_topology/07_09_topology_mutations --include example --seed 0
```

Expected result: Workers grow from two to three, shrink to one, and are removed. Unchanged
members keep their PIDs and state. Replacing the observer changes only its
runtime. Invalid counts and duplicate additions leave the accepted state intact.

## Important behavior

The Action returns complete root state and mutation directives. AgentServer
validates the candidate, commits it, and reconciles the member runtimes.
Use `Server.await_ready(server)` after each accepted mutation.

Replacement starts the selected member from its declared initial state. It
does not copy the old member state. Removal stops the member supervisor.

## Limits

A post-commit runtime failure does not roll back the accepted definition.
This example does not promise effect replay, remote placement, or a
coordinated snapshot of all member states.

## Files

- [Source](mutations.ex)
- [Cell Agent](../support/cell.ex)
- [Tests](../../../test/examples/07_topology/07_09_topology_mutations/mutations_test.exs)
- [Test runtime assertions](../../../test/examples/support/agent_topology_assertions.ex)

The add Action declares `count: state(:worker_count)`. A state-only command
can then resize that group without changing its declaration. `Diff.between/2`
reports the state change; the Server binds the count and reconciles processes.
Explicit `agent_update` can instead replace the count with a fixed integer.

A File-backed test starts the Agent, adds three bound workers, replaces the
observer, hibernates the complete activation, and thaws it twice. Both restores
preserve the complete portable snapshot and revision, including member
count, definitions, and initial inputs. Old processes stop before new ones
start. Members inherit persistence and restore their own confirmed state. The
root saves slot identities so removed and recreated slots get fresh lifetimes.
These independent records are not an atomic family snapshot. Snapshot capture
expands module references into nested definition data.

[Connection Changes](../07_12_connection_changes/README.md) also changes an edge,
hibernates, thaws, and proves that new work follows the saved destination.

Previous: [Nested Agents](../07_02_hierarchy/README.md) | Next: [Connection Changes](../07_12_connection_changes/README.md)
