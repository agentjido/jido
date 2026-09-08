> Seam alignment plan. This document is pending approval.

# Commit and effects alignment

## Status

- Design reviewed: 2026-09-08. All documents in this seam are pending
  approval.
- Code reviewed: `c2825dfb144ce6ccf4223b9401adae84b7c5bbd3` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md), and
  [05 Plugins](../05_plugins/alignment.md). All were used as pending draft
  prerequisites.
- Related inputs: [02 Agent authoring](../02_agent-authoring/design.md) and
  [03 Agent identity](../03_agent-identity/design.md).
- Alignment state: `Blocked`.

The state is blocked because the prerequisite documents are pending and the
write-authority rule conflicts with current code. This document defines
outcomes and gates. It is not the later formal implementation plan.

## Inputs and evidence

### Design inputs

- [Jido V3 vision](../VISION.md): places state commit, Directive production,
  and settlement inside the Bright Line, but keeps external systems and durable
  workflow policy application-owned.
- [Overview design](../00_overview/design.md): defines candidate, commit,
  Directive, recoverable-work, and write-authority targets.
- [Package-boundary design](../90_package-boundaries/design.md): keeps commit
  and Directives in Jido, byte storage in an adapter, and recoverable work in an
  explicit capability.
- [Errors and contracts design](../12_errors-and-contracts/design.md): defines
  target persistence and Directive error meanings, indeterminate writes, and
  portable durable values.
- [Agent design](../01_agent/design.md): keeps one complete immutable Agent,
  combined domain and Plugin state, direct evaluation, and custom checkpoint
  callbacks.
- [Turn-evaluation design](../04_turn-evaluation/design.md): supplies one
  validated candidate and ordered Directive list without commit authority.
- [Plugin design](../05_plugins/design.md): separates pre-commit owned-state
  contribution from post-commit live handling and keeps recoverable Scheduler
  work capability-owned.
- [Agent-identity design](../03_agent-identity/design.md): separates Ref,
  process location, state version, storage revision, and write authority.
- [Target design](design.md): defines the recommended commit-and-effects
  contract.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido/agent.ex:1-17,370-423,439-477` | An Agent is immutable. Direct `cmd/3` returns a candidate and Directives. Default and custom checkpoints are supported. |
| `lib/jido/agent/command/runner.ex:120-153,229-260` | Finalization normalizes output, protects Plugin-owned fields, validates Directive ownership and content, applies Plugin state reducers, and validates the complete transition. |
| `lib/jido/plugin.ex:238-255,280-318,823-875` | Plugin state has separate write ownership. Owned Directive validation and serial state reduction finish before candidate return. |
| `lib/jido/agent_server.ex:1469-1545` | The Server applies live batch checks, calculates one next revision, checkpoints, replaces the live Agent and version, replies, and schedules Directives. |
| `lib/jido/agent_server.ex:1548-1594` | A pre-commit failure keeps prior live state. An uncertain persistence result always stops the Server. Other write errors follow the configured error policy. |
| `lib/jido/agent_server.ex:1639-1875` | Directives are handled serially in list order. The first failure settles the Turn and skips the rest. |
| `lib/jido/agent_server.ex:1012-1029,1725-1756` | A Directive timeout stops its task and creates a timed-out post-commit Outcome. It cannot establish whether external work occurred. |
| `lib/jido/agent_server.ex:2618-2646` | Settlement clears the active Turn and records a terminal Outcome after commit or failure. |
| `lib/jido/agent_server/active_turn.ex:49-129` | One Turn keeps its ID, source and effective Signals, versions, and exact Directive progress until Outcome creation. |
| `lib/jido/agent/turn/outcome.ex:1-190` | A committed Outcome requires the next version to equal the prior version plus one and validates exact Directive counts and failure position. |
| `lib/jido/plugin/directive_context.ex:1-36` | Plugin post-commit work receives Turn ID, source and effective Signals, committed owned state, and state version. |
| `lib/jido/agent_server/directive_runtime.ex:112-205` and `lib/jido/plugin/dispatch.ex:41-64` | Jido Signal Directives preserve the outbound ID and derive trace causation from the effective Signal ID. |
| `lib/jido/agent_server/runtime_checkpoint.ex:14-34` | A nonpersistent named instance stores only the committed Agent and state version. |
| `lib/jido/persistence.ex:59-99,284-371` | Persistence uses atomic revision checks and validates complete portable records. The default record contains an Agent checkpoint, but the checkpoint can come from custom callbacks. |
| `lib/jido/persistence/adapter.ex:6-44` | The adapter owns binary storage and identifies conflict and indeterminate results. It does not own Agent semantics. |

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/agent_server/public_api_test.exs:87-125,230-266` | One complete state commits once, executable input stays separate, and continuation chains finish before commit. |
| `test/jido/agent_server/directive_execution_test.exs:27-117` | Invalid Directive data fails before commit; commit precedes follow-up Signal handling; Plugin context keeps Turn and Signal identity. |
| `test/jido/agent_server/directive_execution_test.exs:134-220,254-348` | Task exit, timeout, external dispatch failure, skip counts, and post-commit state retention are covered. |
| `test/jido/agent_server/runtime_observability_test.exs:15-36` | Debug evidence separates commit and settlement and records before and after versions. |
| `test/jido/agent_server/directive_runtime_test.exs:18-37` | Built-in Signal handling preserves outbound ID and uses the effective input Signal as causation. |
| `test/jido/persistence/indeterminate_write_test.exs:35-94` | Confirmed writes permit commit and dispatch. An indeterminate result, including a lost reply after storage changed, prevents dispatch and later stale-state evaluation. |
| `test/jido/persistence/checkpoint_portability_test.exs:15-49` | Persistence rejects selected nonportable checkpoint values. |
| `test/jido/agent_server/effect_recovery_test.exs:42-209` | REC-01 proves one example of atomic business state and pending intent, restart recovery, stable IDs, duplicate rejection, failed-write behavior, and later Turns during blocked work. |
| `examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex:17-133` | REC-01 defines pending and completed Plugin state, stable work identity, conflict handling, and Signal-based completion. It is example code, not a shipped general core capability. |
| `examples/04_runtime/04_11_recoverable_delivery/delivery_worker.ex:1-70` | The example worker reads committed state on start and poll; a Directive is only a wake-up. |

The superseded gap report recorded 32 passing focused tests on 2026-09-08. This
consolidation does not treat that historical run as proof for missing crash,
custom-checkpoint, generic ordering, revision-zero, or all-write-error cases.

## Retained baseline

- `COMMIT-RB-001`: Direct evaluation produces a candidate and Directives and
  has no live commit or dispatch authority.
- `COMMIT-RB-002`: Live commit replaces one complete Agent and increments its
  state version once, including when state is equal.
- `COMMIT-RB-003`: Candidate, Directive, owner, and live batch validation occur
  before the required checkpoint operation.
- `COMMIT-RB-004`: Runtime or durable checkpoint success precedes live
  replacement and synchronous success.
- `COMMIT-RB-005`: Directive handling starts after commit, uses list order, and
  stops after the first failure.
- `COMMIT-RB-006`: A pre-commit failure preserves the previous snapshot. A
  post-commit failure preserves the new snapshot.
- `COMMIT-RB-007`: Action and Flow I/O is outside rollback guarantees.
- `COMMIT-RB-008`: The Server preserves Turn ID, source and effective Signals,
  version, and Directive progress through settlement.
- `COMMIT-RB-009`: Jido-owned outbound Signal handling derives causation from
  the effective Signal without replacing the outbound ID.
- `COMMIT-RB-010`: The default checkpoint contains combined Agent and Plugin
  state. Complete custom callbacks can change checkpoint content.
- `COMMIT-RB-011`: Ordinary Directive batches, task handles, caller context,
  and active Turn state are transient and are not replayed from checkpoints.
- `COMMIT-RB-012`: Core has no universal outbox, completion cursor, or
  outbox-wide admission gate.
- `COMMIT-RB-013`: REC-01 demonstrates capability-owned recoverable work. It
  does not establish a general core delivery API or exactly-once behavior.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `COMMIT-GAP-001` | `COMMIT-REQ-001` to `COMMIT-REQ-006` | Agent, Runner, Plugin, Server, Persistence, and Signal-dispatch code above | Ownership works but is spread across module documentation. | `Retain`; publish one boundary contract |
| `COMMIT-GAP-002` | `COMMIT-REQ-007` to `COMMIT-REQ-011` | Server commit and Outcome validation | Complete replacement and one-revision behavior work. | `Retain` |
| `COMMIT-GAP-003` | `COMMIT-REQ-012` to `COMMIT-REQ-015` | Runner and Server validation paths | Validation is split correctly, but no one matrix proves all checks precede storage. | `Retain`; strengthen evidence |
| `COMMIT-GAP-004` | `COMMIT-REQ-016` to `COMMIT-REQ-019` | Server commit sequence and persistence tests | Write, replacement, reply, and first Directive order work. | `Retain` |
| `COMMIT-GAP-005` | `COMMIT-REQ-020` and `COMMIT-REQ-021` | State-machine head consumption and failure tests | Failure skip order is proved. Three-entry successful generic Plugin order has only indirect evidence. | `Retain`; add focused evidence |
| `COMMIT-GAP-006` | `COMMIT-REQ-022` and `COMMIT-REQ-023` | Commit and settlement code, debug tests | Internal settlement order works. No public wait contract exists. | `Retain`; state the scope |
| `COMMIT-GAP-007` | `COMMIT-REQ-024` to `COMMIT-REQ-027` | Failure branches and indeterminate-write tests | State atomicity works. No focused test proves retained external I/O after later evaluation failure. | `Retain`; add external-I/O evidence |
| `COMMIT-GAP-008` | `COMMIT-REQ-028` | `lib/jido/agent_server.ex:1560-1594` | Only uncertain errors always remove write authority. Known errors can continue under policy. | `Change`; blocked on seams 07 and 08 |
| `COMMIT-GAP-009` | `COMMIT-REQ-029` and `COMMIT-REQ-030` | Directive failure and timeout tests | Commit retention works. Timeout status exists, but effect uncertainty is mainly documentation. | `Retain`; add an effect-before-timeout case |
| `COMMIT-GAP-010` | `COMMIT-REQ-031` and `COMMIT-REQ-032` | Runtime checkpoint excludes the batch | Core has no replay path, but no focused crash test proves non-replay or absence of reconstructed settlement. | `Change evidence` with seams 08 and 13 |
| `COMMIT-GAP-011` | `COMMIT-REQ-033` to `COMMIT-REQ-035` | ActiveTurn, contexts, dispatch code, and tests | Current continuity works for the implemented route order. Seam 04 can change how the effective Signal is selected. | `Retain`; recheck after seam 04 |
| `COMMIT-GAP-012` | `COMMIT-REQ-036` | Checkpoint and runtime-state code | Exclusions work, but the exception for explicitly saved causal data is not one documented contract. | `Retain`; clarify |
| `COMMIT-GAP-013` | `COMMIT-REQ-037`, `COMMIT-REQ-040` to `COMMIT-REQ-044` | REC-01 example and tests | One capability proves the pattern. Core does not ship a general capability. | `Retain as pattern`; do not promote to core behavior |
| `COMMIT-GAP-014` | `COMMIT-REQ-038` | REC-01 uses fixed choices | No reusable contract proves every required retry, ordering, cancellation, acknowledgement, and retention policy. | `Defer` to each capability owner |
| `COMMIT-GAP-015` | `COMMIT-REQ-039` | Custom Agent callbacks and REC-01 default checkpoint | No test combines custom checkpointing with recoverable Plugin intent. | `Change` with seams 01, 05, and 07 |
| `COMMIT-GAP-016` | Durability precondition | Persistent startup restore path | A new persistent Agent can become ready at revision zero without a stored record. | `Defer implementation` to seams 07 and 08; block broad creation claims |
| `COMMIT-GAP-017` | All requirements | Current public results | Commit and Directive errors still use mixed structs, atoms, and tuples. | `Defer` exact mapping to seam 12 while preserving semantics |

## Dispositions of superseded claims

| Superseded claim or proposal | Disposition | Reason and owner |
| --- | --- | --- |
| Add a universal `Jido.Agent.Outbox.Entry`, completion cursor, and `:outbox_blocked` policy. | `Remove` | It would make every Directive durable and block unrelated Turns. Explicit capabilities own recovery policy. |
| Treat every portable Directive as recoverable. | `Remove` | Portability does not save intent or establish replay, acknowledgement, or duplicate behavior. |
| State that core supplies recoverable delivery. | `Correct` | REC-01 is an example compiled outside production `lib`; core only supplies composable primitives. |
| State without qualification that every checkpoint contains all Plugin state. | `Correct` | The default checkpoint does. A custom Agent callback can omit it. |
| Make a successful command confirm external delivery. | `Remove` | Current `call/3` confirms commit before Directive settlement. Capability state defines later completion. |
| Make Turn settlement equal completion of all background business work. | `Remove` | Settlement covers only the ordinary runtime Directive batch for that Turn. |
| Add a public settlement handle or wait operation now. | `Defer` | No current API exists. Seams 08 and 13 must first identify a user need and observation contract. |
| Replay an ordinary Directive batch after Agent Server restart. | `Remove` | The batch is absent from both runtime and durable checkpoints. |
| Infer successful or failed settlement after a crash from the committed revision. | `Remove` | Commit state cannot prove how far transient Directive work progressed. |
| Treat a Directive timeout as proof that its external effect did not occur. | `Remove` | A killed or timed-out task can lose its reply after an external operation completed. |
| Undo committed state after a Directive failure. | `Remove` | Directives run after commit and failure cannot reverse the committed revision. |
| Roll back external Action or Flow I/O after evaluation or commit failure. | `Remove` | Jido does not own the external transaction. Applications own idempotency and compensation. |
| Persist a separate work queue entry after the business checkpoint. | `Remove` as the default pattern | It creates a loss window. Capability intent belongs in the same candidate unless an external transactional service owns another proved boundary. |
| Require a separate completion-only persistence API. | `Remove` | Completion is a new Signal, Turn, and normal commit. |
| Block all later Turns while capability work is pending. | `Remove` | Admission restrictions are capability policy, not a core outbox rule. |
| Persist PIDs, Tasks, timers, clients, callbacks, or in-progress Flows for recovery. | `Remove` | Runtime resources are not portable intent. Store stable desired state and reconstruct resources. |
| Claim exactly-once external effects. | `Remove` | A crash after effect and before acknowledgement can cause a repeat. |
| Claim that OTP receipt or cast `:ok` proves receiver completion. | `Remove` | The capability must define its acknowledgement boundary. |
| Claim distributed ownership, failover, lease, or fencing from remote child placement. | `Defer` | Those contracts belong to later topology or external durable capability owners. |
| Claim power-loss durability or shared multi-node File-adapter ownership from REC-01. | `Remove` | The evidence covers one BEAM and process-level failures only. |
| Put persistence `Record`, lifecycle, or adapter-key shapes in this seam. | `Defer` | Seam 07 owns those values and migrations. |
| Put Agent Server admission, task, restart, and public Outcome availability in this seam. | `Defer` | Seam 08 owns runtime mechanics; seam 13 owns observation channels. |
| Put Signal envelope or trace-field representation in this seam. | `Defer` | `jido_signal` owns those shapes. This seam requires continuity only. |
| Continue after known write failures but stop only after uncertain results. | `Conflicting` | This is current code, but the pending Overview target removes authority after every write error. User approval must select one rule. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the formal plan later, after the user approves the seam.

### Phase 0 — Resolve prerequisites and seam decisions

- Requirements: all `COMMIT-REQ` identifiers.
- Required outcome: approved commit meaning, reply meaning, Directive
  uncertainty, custom-checkpoint duty, capability boundary, and write policy.
- Constraints: do not define persistence records, Agent Server mechanics,
  Signal fields, or a general delivery product here.
- Compatibility: no runtime change.
- Verification: review each `COMMIT-DEC` item and all prerequisite blockers.
- Exit criteria: prerequisites are approved or replaced by explicit
  assumptions, and the write-authority conflict has one decision.

### Phase 1 — Lock the retained commit contract

- Requirements: `COMMIT-REQ-001` to `COMMIT-REQ-027`, except later evidence
  items noted in the gap register.
- Required outcome: public docs and tests use one candidate, validation,
  checkpoint, replacement, reply, handling, and settlement order.
- Constraints: preserve direct `cmd/3`, live `call/3`, one revision per Turn,
  and current post-commit error policy behavior unless Phase 2 changes it.
- Compatibility: no public entry is removed.
- Verification: focused direct, live, validation, persistence, Outcome, and
  Directive order tests.
- Exit criteria: the retained sequence has no conflicting public statement.

### Phase 2 — Align failure and interrupted-settlement rules

- Requirements: `COMMIT-REQ-028` to `COMMIT-REQ-032`.
- Required outcome: one approved write-authority rule, explicit timeout
  uncertainty, and proved ordinary-batch non-replay after Server loss.
- Constraints: storage result meanings come from seam 07; runtime restart and
  Outcome publication come from seams 08 and 13.
- Compatibility: migrate current known-write-error continuation only after
  caller and error-policy behavior has replacement evidence.
- Verification: known no-write, conflict, indeterminate, lost-reply,
  effect-before-timeout, and crash-during-batch cases.
- Exit criteria: every failure point has one state, dispatch, authority, and
  settlement result.

### Phase 3 — Prove continuity and explicit recoverable work

- Requirements: `COMMIT-REQ-033` to `COMMIT-REQ-044`.
- Required outcome: source and causation continuity remains correct, custom
  checkpoints preserve declared durable intent, and every capability states
  its own recovery contract.
- Constraints: no universal outbox, exactly-once claim, or persisted runtime
  handle.
- Compatibility: audit existing custom callbacks before enforcing a new
  durability declaration rule.
- Verification: source/effective identity, outbound causation, default and
  custom checkpoints, worker restart, duplicate, conflict, retention, and
  unrelated-Turn cases.
- Exit criteria: each declared recovery guarantee has portable committed intent
  and passing failure-boundary evidence.

### Phase 4 — Close downstream and release evidence

- Requirements: all approved `COMMIT-REQ` identifiers.
- Required outcome: seams 07, 08, 13, and 99 use the same approved boundary.
- Compatibility: no supported API changes without its owner-seam migration.
- Verification: format, compile, focused tests, full package tests, and the
  compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` entry for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `COMMIT-REQ-001` to `COMMIT-REQ-006` | Agent, Runner, Plugin, Server, Persistence, and Signal-dispatch code above | Public ownership contract and architecture check | `Proven` |
| `COMMIT-REQ-007` to `COMMIT-REQ-011` | `lib/jido/agent_server.ex:1493-1545`; Outcome version validation | Complete replacement and equal-state Turn tests | `Proven` |
| `COMMIT-REQ-012` to `COMMIT-REQ-015` | Runner and live batch validation; invalid Directive tests | One table proving each check precedes checkpoint work | `Partial` |
| `COMMIT-REQ-016` and `COMMIT-REQ-017` | Runtime checkpoint, persistence save, and commit sequence | Explicit runtime-checkpoint and compare-and-swap order tests | `Proven` |
| `COMMIT-REQ-018` and `COMMIT-REQ-019` | Commit action order and blocked-Directive tests | Stable synchronous reply and first-handler ordering tests | `Proven` |
| `COMMIT-REQ-020` and `COMMIT-REQ-021` | Head-first state machine and skip-count tests | Three successful generic Plugin Directives plus fail-at-index cases | `Partial` |
| `COMMIT-REQ-022` and `COMMIT-REQ-023` | Commit/settlement code and debug evidence | Terminal event order with zero, success, failure, exit, and timeout batches | `Proven` |
| `COMMIT-REQ-024` and `COMMIT-REQ-025` | Pre-commit failure code and no-rollback module docs | A real external write followed by evaluation failure | `Partial` |
| `COMMIT-REQ-026` and `COMMIT-REQ-027` | Persistence failure and indeterminate-write tests | Known failure, conflict, indeterminate, exception-after-write matrix | `Proven` |
| `COMMIT-REQ-028` | Current uncertain-write stop only | Every write error removes authority before new evaluation | `Conflict` |
| `COMMIT-REQ-029` | Directive failure tests | Preserve snapshot for every Directive fault class | `Proven` |
| `COMMIT-REQ-030` | Timeout Outcome and dispatch documentation | External effect before lost or timed-out reply | `Partial` |
| `COMMIT-REQ-031` and `COMMIT-REQ-032` | Checkpoints omit active batches | Kill during a blocked batch, restore, prove no replay and no reconstructed settlement | `Missing` |
| `COMMIT-REQ-033` and `COMMIT-REQ-034` | ActiveTurn, Plugin context, and Directive execution tests | Recheck after approved route and Plugin facet changes | `Proven` for current path; target migration is `Partial` |
| `COMMIT-REQ-035` | Directive runtime and direct causation test | Built-in, Plugin Dispatch, parent, child, and external target matrix | `Proven` |
| `COMMIT-REQ-036` | Runtime and durable checkpoint shapes | Explicit exclusion tests plus saved causal-data capability case | `Partial` |
| `COMMIT-REQ-037` | REC-01 candidate and stored-state tests | Public capability declaration rule | `Proven` for REC-01; core rule is `Partial` |
| `COMMIT-REQ-038` | REC-01 documents selected policies | Contract tests for each capability that claims recovery | `Partial` |
| `COMMIT-REQ-039` | Default checkpoint only | Custom checkpoint with pending Plugin intent and required causation | `Missing` |
| `COMMIT-REQ-040` and `COMMIT-REQ-041` | REC-01 restart and completion tests | Repeat for every shipped recoverable capability | `Proven` for REC-01 |
| `COMMIT-REQ-042` and `COMMIT-REQ-043` | REC-01 duplicate, conflict, completion, and restore tests | Retention-boundary test for each shipped capability | `Partial` |
| `COMMIT-REQ-044` | REC-01 blocked-delivery test | Capability admission-policy contract where stricter order is required | `Proven` for REC-01 |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Direct execution | Keep `Jido.Agent.cmd/3` and its candidate-plus-Directives result. Do not add commit meaning to it. |
| Live calls | Keep `Jido.AgentServer.call/3` returning at commit. Any future settlement wait needs a separate approved public contract. |
| State version | Keep one increment for every successful Turn, including equal state. Do not add a no-op commit class. |
| Directive order | Keep list order, stop-at-first-failure, and current error-policy selection. |
| Persistence errors | Preserve current public results until seam 12 defines replacements. Change known-error continuation only with seams 07 and 08 and explicit rollout tests. |
| Checkpoints | Keep version-1 maps and complete custom callbacks. Add preservation validation only after an audit and an approved declaration or migration rule. |
| Recoverable work | Keep REC-01 and Scheduler behavior. Do not present the example as a general production API. |
| Signal identity | Keep current outbound Signal IDs and trace compatibility fields. Let `jido_signal` own any format migration. |
| Outcomes | Keep current Outcome fields and stages until seams 08 and 13 approve a compatibility path. |
| Stored data | This seam defines no record rewrite. Seam 07 owns initial records, record versions, keys, tombstones, and rollback. |

A rollback of later implementation must restore commit order and error policy as
one compatible unit. It must not retain a new write-authority stop rule while
restoring an older caller contract that expects the same activation to
continue.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `COMMIT-BLK-001` | `Blocker` | 00 Overview | Commit, recoverable-work, and all-write-error requirements are pending approval. | Approve or change the Overview decisions. |
| `COMMIT-BLK-002` | `Blocker` | 90 Package boundaries | Core, adapter, and capability ownership is pending approval. | Approve or change the package boundary. |
| `COMMIT-BLK-003` | `Blocker` | 12 Errors and contracts | Final persistence, timeout, and Directive codes and portable-value paths are pending. | Approve the error contract without changing commit semantics. |
| `COMMIT-BLK-004` | `Blocker` | 01 Agent | Combined state, complete replacement, and custom checkpoint rules are pending. | Approve the Agent contract and checkpoint preservation duty. |
| `COMMIT-BLK-005` | `Blocker` | 04 Turn evaluation | The fixed source-Signal route and final candidate contract are pending. | Approve one evaluator output before commit implementation changes. |
| `COMMIT-BLK-006` | `Blocker` | 05 Plugins | Facet roles, contribution order, and custom-checkpoint composition are pending. | Approve the pre-commit and post-commit Plugin split. |
| `COMMIT-BLK-007` | `Blocker` | 07 Persistence, 08 Agent Server | Current code and target design disagree about authority after known write errors. | Select all-error stop or revise the Overview target. |
| `COMMIT-BLK-008` | `Blocker` | 07 Persistence, 08 Agent Server | Revision-zero Agents are not durable before their first write. | Define and prove initial active-record creation before broad durability claims. |
| `COMMIT-BLK-009` | `Assumption` | 08 Agent Server, 13 Observability | Settlement remains a runtime and observation boundary, not a new wait API. | Confirm public Outcome availability and interruption reporting. |
| `COMMIT-BLK-010` | `Assumption` | 03 Agent identity | Stable Ref, state version, storage revision, and write authority remain separate. | Keep commit context from treating any one value as the others. |
| `COMMIT-BLK-011` | `Blocker` | Capability owners | No general production delivery capability is defined in core. | Give each shipped capability its own recovery and acceptance contract. |

## Completion criteria

- [ ] The user has approved or changed every `COMMIT-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `COMMIT-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] Validation, checkpoint, replacement, reply, Directive, and settlement
      order have direct tests.
- [ ] Persistence failures have one approved authority rule across seams 06,
      07, 08, and 12.
- [ ] Ordinary-batch crash and timeout uncertainty have focused evidence.
- [ ] Every durability claim states its adapter, checkpoint, activation,
      acknowledgement, retry, duplicate, and retention conditions.
- [ ] Custom checkpoints preserve every field required by a declared recovery
      guarantee.
- [ ] Dependent seam documents use the approved commit contract.
- [ ] After approval, the formal implementation plan is created separately.
