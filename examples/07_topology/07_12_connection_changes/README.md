# 07_12 Connection Changes

An Action redirects an output while both destination Agents keep their processes and state.

## What you will learn

- How connection add, remove, update, and replace operate on accepted data.
- How output from a mutation Turn uses the newly accepted connections.
- How File-backed hibernate and thaw preserve changed connections.

## Read the code

Read [the Agent](connection_changes.ex), then [the behavior tests](../../../test/examples/07_topology/07_12_connection_changes/connection_changes_test.exs).
The destinations use the shared [Cell Agent](../support/cell.ex). Tests use the [shared runtime assertions](../../../test/examples/support/agent_topology_assertions.ex).

## Run it

```sh
mix test test/examples/07_topology/07_12_connection_changes --include example --seed 0
```

Expected result: work first reaches the left Agent, then a redirect Turn sends work to the right Agent. A later fan-out reaches both. PIDs remain unchanged during edits. Repeated redirection fails without a commit. After hibernate and thaw, new output still reaches the saved right destination.

## Important behavior and limits

Connections are identified by source, destination, and path. To redirect an
edge, remove the old edge and add the new edge in one batch. `connection_update`
changes its delivery field; `connection_replace` supplies the complete edge.
Connections fan out to all matching destinations, regardless of declaration
order. This differs from first-match route selection.

Use `Server.await_ready/1` after mutations. The root reply confirms the root
commit, so tests wait separately for destination commits. The runtime does not
roll back a committed topology after a later delivery failure.

The persistence test uses a temporary File store. It compares the complete
portable snapshot and runtime revision before and after thaw, then sends work
to prove the restored connection. Snapshot capture expands module references
into nested definition data. Each persistent member restores its own confirmed
record. The right member retains its earlier total of 5, then receives 4 and
reaches 9. These independent records do not form an atomic family snapshot.

Previous: [Topology Mutations](../07_09_topology_mutations/README.md) | Next: [Application examples](../../08_applications/README.md)
