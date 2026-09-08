> Target seam design. This document is pending approval.

# Commit and effects design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. Code remains canonical for current behavior.

## Scope and owner

- Owner: the Jido live commit semantic boundary, executed by `Jido.AgentServer`.
- In scope: candidate-to-live transition, complete snapshot replacement,
  revision advancement, validation and visibility order, caller confirmation,
  Directive order and failure atomicity, source and causation continuity, and
  the distinction between ordinary Directives and recoverable work.
- Out of scope: Turn selection and candidate production; Plugin facet shapes;
  Agent Server admission, task, supervision, and lifecycle policy; persistence
  record and adapter formats; Signal envelope and transport semantics; durable
  workflow orchestration; external receiver transactions; and exactly-once
  delivery.

## Model

The commit boundary receives one current live snapshot, one fully evaluated
candidate, one ordered Directive list, and one active Turn context:

```text
validated candidate + validated Directive batch
  -> required checkpoint write
  -> replace live Agent + advance state version once
  -> confirm commit to caller
  -> handle Directives in list order
  -> settle the Turn
```

The commit step is effect-free with respect to application and Directive work.
It can write the required Jido checkpoint, replace the authoritative live
snapshot, and record semantic commit observation. It does not call application
effect handlers. This use of “effect-free” does not mean that persistence is a
pure function.

An Agent state commit is complete replacement, not a sequence of visible
field mutations. The candidate already includes executable domain-state output
and ordered Plugin-owned state contributions. The Server either keeps the
previous complete Agent and version or makes the candidate and next version
authoritative. Runtime state changed by a built-in Directive is post-commit
runtime work. It is not part of the Agent state commit.

There are three distinct completion points:

| Point | Meaning |
| --- | --- |
| Evaluation return | One candidate and Directive list exist; nothing is live. |
| Commit confirmation | The checkpoint succeeded and the candidate is authoritative. |
| Turn settlement | The ordinary Directive batch completed or stopped at its first failure. |

External business completion is a fourth, capability-specific point. It is not
implied by Turn settlement.

### Ownership boundaries

| Owner | Owns here | Must not own here |
| --- | --- | --- |
| Turn evaluator, seam 04 | Produces one validated candidate and ordered Directive list. | Live state, revision, persistence, dispatch, or settlement. |
| Plugin boundary, seam 05 | Applies pure owned-state contributions before candidate return and defines owned post-commit handlers. | Commit choice, storage result, or foreign state. |
| Agent Server, seams 06 and 08 | Executes the live commit order and coordinates post-commit handling. | Candidate semantics, storage durability strength, or Signal envelope meaning. |
| Persistence, seam 07 | Encodes, validates, and atomically writes the record through its adapter. | Candidate production, Directive dispatch, or external effect acknowledgement. |
| Signals, `jido_signal` | Defines Signal identity, context, trace fields, dispatch, and bus behavior. | Agent commit, state revision, or durability of Agent work. |

## Requirements

These stable EARS requirements are pending approval.

### Boundary and ownership

`COMMIT-REQ-001`: When Turn evaluation succeeds, the Turn evaluator shall
return one complete candidate Agent and one ordered Directive list without
making the candidate live.

`COMMIT-REQ-002`: When direct `Jido.Agent.cmd/3` evaluation succeeds, the Agent
boundary shall return the candidate and Directives without committing state or
handling a Directive.

`COMMIT-REQ-003`: When a live Turn reaches commit, the Agent Server shall be the
only component that can make the candidate authoritative for that activation.

`COMMIT-REQ-004`: When a Plugin contributes owned state before commit, the
Plugin boundary shall complete that contribution before the Turn evaluator
returns the candidate.

`COMMIT-REQ-005`: When the persistence boundary writes a commit record, it
shall not invoke a Directive handler or change candidate contents.

`COMMIT-REQ-006`: When the Signal boundary dispatches a post-commit Signal, it
shall not change the source Agent's committed snapshot or state version.

### Complete replacement and validation

`COMMIT-REQ-007`: When the Agent Server accepts a candidate for commit, it shall
accept one complete validated Agent value and not a partial state patch.

`COMMIT-REQ-008`: When a live commit succeeds, the Agent Server shall replace
the previous complete Agent snapshot with the complete candidate snapshot.

`COMMIT-REQ-009`: When a live commit succeeds, the Agent Server shall increase
the state version by exactly one.

`COMMIT-REQ-010`: When a candidate state value equals the previous state value,
the Agent Server shall still increase the state version by exactly one for a
successful Turn.

`COMMIT-REQ-011`: While a candidate has not committed, the Agent Server shall
not expose any part of that candidate as live Agent state.

`COMMIT-REQ-012`: When the Turn evaluator finalizes a candidate, it shall
validate the complete Agent transition and every Directive before returning
success.

`COMMIT-REQ-013`: When the Agent Server receives a candidate and Directive
list, it shall validate the complete live Directive batch policy before it
starts the required checkpoint write.

`COMMIT-REQ-014`: If candidate or Directive validation fails, then the Agent
Server shall preserve the previous live Agent and state version.

`COMMIT-REQ-015`: If candidate or Directive validation fails, then the Agent
Server shall start no Directive from that batch.

### Commit, reply, handling, and settlement order

`COMMIT-REQ-016`: When a live Turn commits without configured persistence, the
Agent Server shall write the in-instance runtime checkpoint before it replaces
the live Agent snapshot.

`COMMIT-REQ-017`: Where persistence is configured, when a live Turn commits,
the Agent Server shall receive confirmed success for the required atomic
compare-and-swap before it replaces the live Agent snapshot.

`COMMIT-REQ-018`: When a synchronous live call succeeds, the Agent Server shall
send the success reply only after the candidate and next state version are
authoritative.

`COMMIT-REQ-019`: When a committed Turn has Directives, the Agent Server shall
start the first Directive only after the candidate and next state version are
authoritative.

`COMMIT-REQ-020`: When a committed Turn has more than one Directive, the Agent
Server shall start them serially in their returned list order.

`COMMIT-REQ-021`: If one Directive fails, exits, or reaches its operation limit,
then the Agent Server shall stop that batch and skip every later Directive.

`COMMIT-REQ-022`: When a committed Turn has no Directives, the Agent Server
shall settle that Turn at the commit boundary.

`COMMIT-REQ-023`: When a committed Turn has Directives, the Agent Server shall
settle that Turn only after all Directives complete or one Directive stops the
batch.

### Failure atomicity and uncertainty

`COMMIT-REQ-024`: If a Turn fails before commit, then the Agent Server shall
preserve the previous committed Agent and state version.

`COMMIT-REQ-025`: If executable code performs external I/O before a Turn fails,
then the Jido commit boundary shall not report that I/O as rolled back.

`COMMIT-REQ-026`: If a required checkpoint write is not confirmed, then the
Agent Server shall not make the candidate live.

`COMMIT-REQ-027`: If a required checkpoint write is not confirmed, then the
Agent Server shall not start the related Directive batch.

`COMMIT-REQ-028`: If a required persistence write returns any error or an
indeterminate result, then the Agent Server shall remove that activation's
write authority before it admits another Turn.

`COMMIT-REQ-029`: If post-commit Directive handling fails, then the Agent
Server shall preserve the committed Agent and state version.

`COMMIT-REQ-030`: If a Directive operation reaches its time limit, then the
Agent Server shall report a timed-out settlement without claiming that the
external effect did not occur.

`COMMIT-REQ-031`: If an Agent Server exits during ordinary Directive handling,
then a later activation shall not replay that transient Directive batch as
core recovery work.

`COMMIT-REQ-032`: If an Agent Server exits before it creates a terminal Turn
Outcome, then a later activation shall not report that Turn as settled from the
runtime checkpoint alone.

### Source and causation continuity

`COMMIT-REQ-033`: While one live Turn remains active, the Agent Server shall
preserve its Turn ID, unchanged source Signal, and selected effective Signal
through commit and settlement.

`COMMIT-REQ-034`: When the Agent Server calls a Plugin Directive handler, it
shall provide that Turn's ID, source Signal, effective Signal, committed
Plugin-owned state, and committed state version.

`COMMIT-REQ-035`: When Jido dispatches a Signal for a post-commit Signal
Directive, the Jido Signal-dispatch boundary shall preserve the outbound Signal
ID and set its causation identity from the effective Signal ID.

`COMMIT-REQ-036`: When the Agent Server stores a checkpoint, it shall exclude
the transient Directive batch, caller context, task handles, and Turn runtime
state unless an explicit capability first places required portable data in
Agent or Plugin-owned state.

### Explicit recoverable work

`COMMIT-REQ-037`: Where a capability promises recoverable work, when it accepts
new work, the capability shall place portable pending intent and the related
business state in the same candidate Agent.

`COMMIT-REQ-038`: Where a capability promises recoverable work, the capability
shall define a stable work ID, portable input, acknowledgement meaning, retry
policy, ordering policy, cancellation policy, retention policy, and duplicate
or conflict rule.

`COMMIT-REQ-039`: Where a capability promises recoverable work and custom Agent
checkpoint callbacks are active, the Agent checkpoint boundary shall preserve
every owned state and causation field required to resume that work.

`COMMIT-REQ-040`: Where committed recoverable work is pending, when its worker
starts or restarts, the capability shall read the committed pending state and
resume according to its policy.

`COMMIT-REQ-041`: When recoverable work completes, the capability shall report
completion through a new Signal and a new normal Agent Turn.

`COMMIT-REQ-042`: If recoverable external work can complete before its
acknowledgement commits, then the capability shall use its stable work ID to
detect a repeated or conflicting operation.

`COMMIT-REQ-043`: When recoverable-work completion commits, the capability
shall preserve enough completed-ID state to meet its declared duplicate and
retention policy after restart.

`COMMIT-REQ-044`: While recoverable work remains pending, the Jido core runtime
shall not block unrelated later Turns unless that capability declares and
enforces a narrower admission policy.

## Public contract

This seam adds no required public commit function, transaction object, outbox
entry, completion cursor, or settlement-wait function. `Jido.Agent.cmd/3`
remains the process-free candidate boundary. `Jido.AgentServer.call/3` remains
the live command boundary and returns after commit or pre-commit failure. A
successful call does not confirm Directive settlement or external business
completion.

`Jido.Agent.Turn.Outcome` remains the terminal runtime value. Its exact public
availability and observation channels belong to seams 08 and 13. This seam
requires only that its commit and Directive summary match the actual order.

### Durability levels

| Configuration | Commit confirms | Does not confirm |
| --- | --- | --- |
| No persistent adapter | In-instance runtime checkpoint was written before live replacement. | Survival of a complete Jido instance or machine loss. |
| Persistent adapter | The configured adapter confirmed the required compare-and-swap before live replacement. | Stronger durability than that adapter and deployment document. |
| Explicit recoverable capability | Pending intent was part of the committed candidate, subject to checkpoint preservation. | Delivery, acknowledgement, external completion, or exactly-once execution. |

The default Agent checkpoint contains the complete combined Agent and Plugin
state. A custom checkpoint is valid current behavior, but it can weaken a
capability's recovery claim. The capability and Agent author must make that
composition explicit.

## Invariants

- `COMMIT-INV-001`: One successful Turn causes one complete Agent replacement
  and one state-version increment.
- `COMMIT-INV-002`: No application or Directive effect handler runs inside the
  commit step.
- `COMMIT-INV-003`: No post-commit failure changes whether the commit occurred.
- `COMMIT-INV-004`: An ordinary Directive batch is transient runtime state.
- `COMMIT-INV-005`: Recoverable work exists only when portable intent is part
  of committed owned state.
- `COMMIT-INV-006`: Stable Agent identity, runtime location, state version, and
  write authority are separate values.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 07 Persistence | One validated candidate and next revision reach the write boundary before visibility; storage does not own Directive work. |
| 08 Agent Server | One explicit sequence governs validation, checkpoint, replacement, reply, Directive handling, and settlement. |
| 13 Observability | Commit and settlement are separate semantic events with one Turn identity and accurate failure position. |
| 99 Delivery | Every commit, failure, causation, and recovery claim has a stable acceptance identifier. |
| Capability packages | Core permits portable intent in Agent or Plugin state but does not supply a universal outbox or exactly-once guarantee. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `COMMIT-DEC-001` | What is a live state commit? | Replace one complete immutable Agent snapshot and increment the state version once. | Partial mutation and no-op commit categories stay outside the contract. |
| `COMMIT-DEC-002` | What does synchronous success mean? | Confirm commit only; add no settlement wait API here. | Callers use capability state for external completion and observation for settlement. |
| `COMMIT-DEC-003` | What happens after any persistence write error? | Remove write authority before another Turn, matching the Overview target. | Current continuation after known errors must change with seams 07 and 08. |
| `COMMIT-DEC-004` | What happens to an ordinary batch after Server loss? | Do not replay it and do not reconstruct settlement from a checkpoint. | Ordinary work remains explicitly transient. |
| `COMMIT-DEC-005` | Does a Directive timeout prove absence of an effect? | No. Report runtime timeout and require application duplicate policy for retries. | Settlement status is not an external transaction result. |
| `COMMIT-DEC-006` | How does custom checkpointing affect recoverable work? | Require preservation of every owned field used by the declared guarantee. | Custom callbacks remain supported but cannot silently weaken durability claims. |
| `COMMIT-DEC-007` | Does core provide a general durable delivery facility? | No. Keep it capability-owned and evaluate any reusable implementation as a separate public Plugin contract. | Core keeps no universal outbox, cursor, or global admission gate. |
