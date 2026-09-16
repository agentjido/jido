# Ownership, Orphans, and Remote Children

An Agent can own logical child relationships. The parent owns each tag,
lifecycle policy, and delivery path. Runtime state owns process handles.

## Use Stable Tags

`spawn_child/3` starts a child after the parent commit. The tag identifies the
relationship inside that parent. A tag that is already in use is not a free
slot for another child.

Use `emit_to_child/2` and `emit_to_parent/1` for messages through the logical
relationship. Use `stop_child/2` to stop and remove one tracked child. Use
`adopt_child/3` only when application policy assigns an existing child to a new
parent.

`StopChild` and `AgentServer.stop_child/3` accept a reason. A child still owned
by its DynamicSupervisor exits with `:shutdown` when removed. The given reason
applies only if the child is no longer supervised or is a standalone tracked
process. Do not use this reason as a domain completion result; use a Signal for
that result.

## Select Parent-Death Policy

| Policy | Child behavior |
| --- | --- |
| `:stop` | Stop when the logical parent exits |
| `:continue` | Keep running without that parent |
| `:emit_orphan` | Keep running and receive an orphan Signal |

Choose `:continue` or `:emit_orphan` only when the child has a clear rule for
new ownership, pending work, and replies.

Child-started, child-exit, and orphaned Signals let Agent routes update domain
state. A process exit alone is not a business completion record.

## Bound Dynamic Workers

Store pending job IDs, running assignments, and capacity in parent domain
state. Start only the available number of workers. When a result Signal
commits, release its slot and start the next job.

Keep job identity separate from child activation. A restarted child can run the
same job. Use the job ID for duplicate detection and external idempotency.

## Treat Remote Starts As Uncertain

Pass `node:` to `spawn_child/3` for a remote child. The remote node must run the
same named Jido instance and have compatible Agent code.

A timeout or node disconnect does not prove that the child never started. Retry
with the same logical request, then reconcile the remote result. Local Registry
and relationship data do not create cluster-wide ownership authority.

While `AgentServer.status/1` shows a `pending_child_spawns` entry for a tag,
retry only the same `SpawnChild` Directive with the same target node, options,
and tag. A changed target or `StopChild` returns `:child_spawn_pending`; it does
not cancel the request. Restore the target connection and retry the original
Directive. Then check `AgentServer.children/1` and the target Agent identity.
When the child becomes tracked, use `StopChild` if it must stop. If the old
request is closed and no child exists, the retry reports
`:spawn_request_closed` and clears the pending entry; a later request can start
a new generation. Do not reuse the tag while the old result is unknown. If the
target cannot be checked, keep the request unresolved and use an operator rule
to inspect both nodes before any new parent activation. Core has no public
pending-start cancellation operation.

The parent must save the child relationship before it accepts a late online
notice and emits `ChildStarted`. If that write fails, it stops the late child
and keeps the request pending. A later retry can report
`:spawn_request_closed` and clear that old request. The write is required for
restored ownership; an online notice alone is not enough.

`EmitToChild` and `EmitToParent` send relative Signals by asynchronous cast.
A successful Directive means that Jido queued the cast; it does not mean that
the receiving Agent committed a Turn. For important work, commit a stable work
ID in the sender's state, let the receiver send an acknowledgement Signal only
after its own commit, and clear the pending ID when the sender commits that
acknowledgement. The receiver must ignore a repeated work ID.

See [Start Child Agents](child-agents.livemd),
[Topology Definitions](topology-definitions.md), and
[Extension Boundaries](extension-boundaries.md).
