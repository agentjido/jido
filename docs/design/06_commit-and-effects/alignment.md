> The implemented commit baseline remains. The owned-work authority refinement
> is pending approval.

# Commit and effects alignment

## Status

- Implementation reviewed: 2026-09-09 on branch `v3-spike`.
- Prerequisites: package boundaries, portable error values, Agent state and
  identity, source-Signal Turn selection, and owner-specific Plugin facets are
  present.
- Alignment state: `Implemented with deferred owner integrations`.
- Refinement state: `Not implemented` for `COMMIT-REQ-045` through
  `COMMIT-REQ-049`.

The live commit order, failure boundary, Directive order, and write-authority
rule are implemented. Persistence record composition remains with seam 07.
Revision-zero startup durability is implemented across seams 07 and 08. Public
interrupted-settlement observation remains with seam 13.

The proposed Agent Server shape moves blocking checkpoint, persistence, and
post-commit execution into owned workers. This does not move commit authority.
The Runtime remains the only component that can accept a current receipt,
publish the candidate, advance the version, reply, change Directive position,
or settle the Turn.

This execution state is not approval of all requirements in the target design.

## Selected architecture

The Agent Server receives one complete candidate and one ordered Directive
list from Turn evaluation. It owns this sequence:

```text
complete candidate + complete Directive batch
  -> live batch validation
  -> required runtime or durable checkpoint
  -> complete Agent replacement + one version increment
  -> synchronous commit reply
  -> serial Directive handling
  -> terminal settlement
```

The required checkpoint must report success before live replacement. Every
persistence write error removes the current activation's write authority. The
caller receives the persistence failure, the related Directives do not start,
and the Server stops with `{:shutdown, {:persistence_failed, reason}}`.

A later activation must restore storage before it continues. This rule applies
to a confirmed conflict, a known adapter error, and an indeterminate result.
The meanings are different: a conflict confirms that this write did not win;
an indeterminate result can follow a completed write.

## Boundary results

### Commit and caller result

Direct `Jido.Agent.cmd/3` returns a candidate and Directives without changing a
live Agent. Live commit replaces one complete immutable Agent and increments
the state version once, including when the state value is equal. A successful
live call confirms that boundary only.

All candidate, ownership, Directive, limit, and terminal-position validation
finishes before the checkpoint. The checkpoint finishes before replacement,
the caller reply, or Directive dispatch.

### Failures and external work

A failure before commit preserves the previous live Agent and state version.
It does not roll back external I/O that an Action or Flow already performed.

A Directive starts only after commit. A Directive failure, exit, or timeout
preserves the committed Agent and stops the remaining batch. A timeout is a
runtime result. It does not prove whether an external receiver applied an
effect before the reply was lost or the task stopped.

### Transient and recoverable work

An ordinary Directive batch, its task handles, caller data, and Active Turn are
not stored in runtime or durable checkpoints. A restored Server does not replay
that batch or reconstruct a terminal Outcome from the committed revision.

Core has no universal outbox, global pending-work cursor, or exactly-once
external-effect guarantee. A capability that promises recovery must own its
portable pending intent, stable operation ID, acknowledgement, retry, ordering,
cancellation, retention, and duplicate policy. Completion returns through a
new Signal and a normal new Turn.

The default Agent checkpoint includes the sole complete Agent state map, with
its domain and Plugin-owned fields. A Persistence facet can convert its paired
owned value. A custom complete checkpoint bypasses that conversion and keeps
its complete callback contract.

## Canonical source

| Source | Implemented contract |
| --- | --- |
| `lib/jido/agent/runner.ex` | Produces and validates one complete candidate and ordered Directive list without live authority. |
| `lib/jido/agent_server.ex` | Validates the live batch, checkpoints, replaces the Agent, advances one version, replies, handles Directives serially, and settles. Every persistence failure forces activation stop. |
| `lib/jido/agent_server/active_turn.ex` | Preserves Turn ID, source and effective Signals, versions, caller, and exact Directive progress during one activation. |
| `lib/jido/agent/turn/outcome.ex` | Validates terminal stage, commit state, version transition, and Directive completion, failure, and skip counts. |
| `lib/jido/agent_server/directive_runtime.ex` | Runs built-in post-commit work without state-commit authority. |
| `lib/jido/agent_server/runtime_checkpoint.ex` | Stores the committed Agent and version, not the transient Directive batch or Active Turn. |
| `lib/jido/persistence.ex` | Performs portable record validation and atomic revision-checked writes without Directive authority. |
| `lib/jido/persistence/adapter.ex` | Distinguishes confirmed conflicts from indeterminate storage results. |

## Executable evidence

| Evidence | Result |
| --- | --- |
| `test/jido/agent_server/commit_boundary_test.exs` | Three Plugin Directives run in returned order after one commit. External Action work remains after later candidate validation fails. A Directive can apply an external effect before timeout. An ordinary batch is not replayed after Server loss and restore. |
| `test/jido/persistence_test.exs` | A confirmed stale-writer conflict returns before state replacement or Directive work, stops the stale activation, and preserves the winning stored record. |
| `test/jido/persistence/indeterminate_write_test.exs` | A confirmed write permits commit. Lost or uncertain replies prevent dispatch and later stale-state evaluation. |
| `test/jido/agent_server/distributed_authority_test.exs` | A stale remote activation stops after a conflict while the replacement keeps the winning revision. This does not claim cluster-exclusive ownership. |
| `test/jido/agent_server/effect_recovery_test.exs` | Failed intent writes expose no live work. Failed acknowledgement writes leave saved intent for a restored activation. |
| `test/jido/plugin/scheduler/occurrence_recovery_test.exs` | Failed Scheduler writes stop the activation. Restoration resumes saved occurrence intent, preserves cancellation, and rejects obsolete generations. |
| Existing Agent Server Directive and observability tests | Candidate and batch validation, one-version commit, reply order, fail-fast Directive handling, source and causation continuity, and commit retention remain covered. |

## Requirement disposition

| Requirement set | State | Evidence or owner |
| --- | --- | --- |
| `COMMIT-REQ-001` to `COMMIT-REQ-006` | `Proven` | Runner, owner-specific Plugin facets, Agent Server, Persistence, and Signal dispatch keep separate authority. |
| `COMMIT-REQ-007` to `COMMIT-REQ-015` | `Proven` | Complete replacement and validation occur before checkpoint and visibility. |
| `COMMIT-REQ-016` to `COMMIT-REQ-023` | `Proven` | Checkpoint, replacement, reply, ordered handling, and settlement order have source and focused test evidence. |
| `COMMIT-REQ-024` to `COMMIT-REQ-030` | `Proven` | Pre-commit state atomicity, external-I/O limits, all-write-error authority loss, post-commit retention, and timeout uncertainty are covered. |
| `COMMIT-REQ-031`, `COMMIT-REQ-032` | `Runtime behavior proven; public observation deferred to seam 13` | Restore does not replay an ordinary batch or infer settlement. Seam 13 owns any public interrupted-settlement signal. |
| `COMMIT-REQ-033` to `COMMIT-REQ-036` | `Proven` | Active Turn, Plugin Directive context, outbound Signal trace, and checkpoint exclusions preserve the boundary. |
| `COMMIT-REQ-037`, `COMMIT-REQ-038`, `COMMIT-REQ-040` to `COMMIT-REQ-044` | `Pattern proven; capability-owned` | Recoverable delivery and Scheduler prove saved intent, stable IDs, later acknowledgement Turns, retry, cancellation, and duplicate rules. Core does not generalize the policy. |
| `COMMIT-REQ-039` | `Proven in seam 07` | Default Plugin owned-slice conversion and complete custom-checkpoint bypass have focused integration tests. |
| `COMMIT-REQ-045` to `COMMIT-REQ-049` | `Missing` | The current commit order is proven, but storage and all post-commit work do not yet use one fenced worker-result contract. |

## Compatibility and migration

- No public commit, transaction, outbox, cursor, or settlement-wait function is
  added.
- `Jido.Agent.cmd/3` remains the direct candidate boundary.
- `Jido.AgentServer.call/3` remains the live commit boundary and keeps its
  existing success and persistence-error result shapes.
- Error policy still applies to ordinary Turn and Directive failures. It
  cannot keep an activation alive after a required persistence write error.
- Existing Directives remain transient. Applications that need recovery must
  save explicit capability state before external execution.
- A retry after any persistence failure must use a new activation restored
  from authoritative storage. Do not retry against the stopped PID.

## Remaining owner work

| Seam | Required follow-up |
| --- | --- |
| 07 Persistence | Complete. Default Persistence facets, custom checkpoint bypass, and revision-zero active records are implemented. |
| 08 Agent Server | Separate blocking storage execution from Runtime publication. Add one fenced receipt contract and keep the all-write-error stop rule. |
| 10 Runtime topology | Own commit and effect workers under the instance Task Supervisor and stop them with the activation. |
| 13 Observability | Define public evidence for a Turn interrupted after commit and before terminal settlement. |
| Capability owners | Define acknowledgement, retry, ordering, cancellation, retention, and duplicate policy for each recoverable operation. |
| 99 Delivery | Keep commit, timeout, interrupted-batch, and recovery acceptance evidence in the final matrix. |

## Completion gate for this seam

- [x] One complete candidate and Directive batch reaches one live commit
      authority.
- [x] Validation and checkpoint finish before replacement, reply, or
      Directive handling.
- [x] Successful Directives run serially in returned order.
- [x] External Action I/O is not reported as rolled back after a later
      pre-commit failure.
- [x] A Directive timeout keeps the commit and does not claim effect absence.
- [x] Every persistence write error removes activation write authority.
- [x] Ordinary Directive work is not replayed after Server loss.
- [x] Recoverable work remains an explicit capability pattern, not a core
      outbox.
- [x] Custom checkpoint preservation is complete in seam 07.
- [x] Revision-zero durable activation is complete for the start-call boundary.
- [ ] A checkpoint or persistence worker has no live publication authority.
- [ ] A post-commit worker has no Directive, relationship, or settlement
      authority.
- [ ] Stale and duplicate worker results cannot publish or advance work.
- [ ] Interrupted-settlement observation is complete in seam 13.
- [ ] The full target design has user approval.
