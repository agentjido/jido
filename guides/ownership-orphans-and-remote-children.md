# Ownership, Orphans, and Remote Children

An Agent can own logical child relationships. The parent owns each tag,
lifecycle policy, and delivery path. Runtime state owns process handles.

## Use Stable Tags

`spawn_agent/3` starts a child after the parent commit. The tag identifies the
relationship inside that parent. A tag that is already in use is not a free
slot for another child.

Use `emit_to_child/2` and `emit_to_parent/1` for messages through the logical
relationship. Use `stop_child/2` to stop and remove one tracked child. Use
`adopt_child/3` only when application policy assigns an existing child to a new
parent.

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

Pass `node:` to `spawn_agent/3` for a remote child. The remote node must run the
same named Jido instance and have compatible Agent code.

A timeout or node disconnect does not prove that the child never started. Retry
with the same logical request, then reconcile the remote result. Local Registry
and relationship data do not create cluster-wide ownership authority.

See [Start Child Agents](child-agents.livemd),
[Topology Definitions](topology-definitions.md), and
[Extension Boundaries](extension-boundaries.md).
