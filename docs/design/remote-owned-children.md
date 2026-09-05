> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Remote owned children

The user agreed to the core contract on 2026-09-04. This document records its
implementation and limits; document review status is tracked in the index.

## Public syntax and ownership

```elixir
Directive.spawn_agent(Worker, :worker, node: target_node)
```

Omit `node` to use the parent's node. The field is an Erlang node atom, not a
string. Placement inside `opts.node` is rejected. Agent Server options remain
inside `opts`. The target must run the same named Jido instance with matching
Agent code. Core never falls back to a local child for an explicit remote node.

The parent owns the logical child relationship. The target Jido instance owns
the child's process, Plugin processes, and execution. Parent and child exchange
Signals through `EmitToChild` and `EmitToParent`. `StopChild` terminates the child
through its owning node's supervisor. Ordinary public commands can use a remote
Agent PID. Public `Jido.stop_agent/3` also accepts a remote PID.

The default parent-death policy stops remote work when the parent activation
exits or its distribution connection is lost. A restarted remote child uses
the original parent activation and cannot restart forever after that parent
has stopped. This applies to the permanent restart policy as well.

## Startup, identity, and uncertain completion

Remote startup uses `directive_timeout` from the parent Server (5 seconds by
default). A timeout or connection loss can occur after the target accepted
the request. Core returns a structured `child_spawn_indeterminate` error and
an `:indeterminate` Turn Outcome. Agent state has already committed; this
error does not roll it back. A command's `{:ok, agent}` reply confirms that
commit, not completion of later Directives.

The parent retains a private request with a generation and opaque reference.
A retry with the same tag, target, Agent, options, metadata, and restart policy
uses the same identity. A changed request cannot replace an unresolved one.
`Server.status/1` exposes unresolved entries under
`runtime.pending_child_spawns`. A verified child-online event resolves a late
start. An existing tracked child still rejects a duplicate spawn tag.
If the child stopped before the parent received that event, a retry returns
`spawn_request_closed` and clears the pending request. A subsequent spawn can
then use a new generation.

The target's `SpawnRegistry` retains the newest request generation for each
parent activation and tag. Its state is in the instance RuntimeStore. A
completed stop closes the request; a late duplicate cannot recreate that child.
A newer request can reuse the tag. Registry process restart retains this
record. Confirmed parent death removes its records. Distribution loss retains
closed generations until the parent can be monitored again; it does not prove
that the parent process is dead.

The target DynamicSupervisor serializes child creation. It checks request
identity before creating or returning a child. An unrelated Agent with the same
id is never adopted as a successful start. Missing code or a missing Jido
instance produces a failure. Stop failure preserves tracking. An unresolved
start cannot be silently discarded by `StopChild`; the request must first
resolve, or the parent activation must stop.

## Limits and subsequent work

This is explicit placement and process ownership. It does not provide a
distributed directory, leases, fencing, automatic failover, sharding, or
exactly-once external effects. Request records survive a SpawnRegistry process
restart within one Jido instance; they are not durable across loss of that
instance or VM. Changing the owning node after a failure requires the later
identity and recovery authority contract.

The connected-node lifecycle, held execution cleanup, duplicate requests,
delayed startup, and closed request records have core tests. DIST-02 extends
these with controlled partitions, reconnect, node loss, and recovery policy.
DIST-03 covers stable identity and authority after node/instance replacement.

See the [implementation results](../examples/dist-01-results.md) for commands,
test evidence, and current limitations.
