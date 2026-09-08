> Seam alignment plan. This document is pending approval.

# Agent Server alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `f072a40b112d229a4ff47b9019c0a0810be60a19` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md), and
  [07 Persistence](../07_persistence/alignment.md), all used as pending draft
  prerequisites.
- Related authoring input: [02 Agent authoring](../02_agent-authoring/alignment.md),
  used for canonical construction and generated live-helper behavior.
- Alignment state: `Blocked` on pending prerequisite and seam decisions.
- Approved decisions: None.

The alignment state is execution status. It is not document approval. This
file defines outcomes and gates. It is not the later implementation plan.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): assigns live Agent state, serial Turns,
  commit, and effects to Agent Server. It leaves application architecture,
  deployment, cluster policy, and transport outside Jido.
- [Overview design](../00_overview/design.md): supplies the pending one-owner,
  commit, write-authority, runtime-checkpoint, Plugin replacement, cancellation,
  and compatibility requirements.
- [Package-boundary design](../90_package-boundaries/design.md): keeps Agent
  Server in local Jido core, preserves current PID and debug APIs during
  migration, and forbids private access by ecosystem packages.
- [Errors design](../12_errors-and-contracts/design.md): supplies pending
  overload, timeout, reentry, cancellation, runtime, and persistence error
  meanings. It keeps defined OTP controls in a protocol registry.
- [Agent design](../01_agent/design.md) and
  [Agent authoring design](../02_agent-authoring/design.md): own canonical
  construction, instance protection, definition revision, and generated live
  helper delegation.
- [Identity design](../03_agent-identity/design.md): makes Ref stable and PID a
  replaceable handle. It keeps PID and ID APIs during additive migration.
- [Turn design](../04_turn-evaluation/design.md): owns source-Signal selection,
  fixed executable choice, candidate assembly, and the executable-code
  non-pinning recommendation.
- [Plugin design](../05_plugins/design.md): owns Agent Server facets, runtime
  readiness, and the matching Plugin-state and state-version bootstrap target.
- [Commit design](../06_commit-and-effects/design.md): owns checkpoint,
  replacement, reply, Directive, settlement, and non-replay order.
- [Persistence design](../07_persistence/design.md): owns initial active records,
  CAS results, tombstones, restore meaning, and the pending all-write-error
  authority rule.
- [Target design](design.md): defines this seam's recommended runtime contract.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido/agent_server.ex:1-47,432-500` | `Jido.AgentServer` is a `:gen_statem`. It owns one live Agent, state version, active Turn, runtime work, and five total phases including initialization. |
| `lib/jido/agent_server.ex:85-430` | Public PID/name operations include startup, call, cast, request, inspection, cancellation, debug, lookup, child controls, snapshot, and hibernation. |
| `lib/jido/agent_server/options.ex:4-136,294-400` | One Zoi-backed option value validates Agent construction, registration, persistence, limits, executable runtime, lifecycle, and open error policies. There is no `turn_timeout` or persistence-operation timeout. |
| `lib/jido/agent_server.ex:441-544` | Startup restores first, validates the Agent, normalizes Plugins, starts Plugin roots, waits for readiness, and then publishes. It does not create a persistent revision-zero record. |
| `lib/jido/agent_server.ex:579-620,1878-1924` | Inspection remains responsive in every phase. Status and snapshot are protocol maps, not target-specific public structs. |
| `lib/jido/agent_server.ex:759-848,1926-1978` | Busy Signals use OTP postponement. A token set bounds only events already seen by the state machine. Full calls fail; full casts are dropped. |
| `lib/jido/agent_server.ex:709-756,1596-1637` | Admission and executable work can be cancelled. Current controls are atoms such as `:idle`, `:directing`, `:stale_turn`, and `:cancelled`. |
| `lib/jido/agent_server.ex:1285-1467` | One ActiveTurn starts before live admission. Admission runs in a supervised task and uses `directive_timeout`. Runner prepares the Turn and `Jido.Exec` runs the selected executable asynchronously. |
| `lib/jido/agent_server.ex:1469-1545` | Runner finalization and live Directive validation precede checkpoint work. A successful commit writes first, replaces the complete Agent, increments one version, replies, and then starts Directives. |
| `lib/jido/agent_server.ex:1548-1594` | Indeterminate persistence failures stop. Confirmed conflicts and other known failures can continue through current error policy. |
| `lib/jido/agent_server.ex:1639-1862` | Directives run in list order after commit. One failure stops the batch. Process-backed work has one Directive timeout and does not roll back state. |
| `lib/jido/agent_server.ex:1981-2008` | Synchronous reentry from admission, executable, and Directive process trees is detected and rejected. |
| `lib/jido/agent_server.ex:2148-2218` | Plugin lifecycle-owner loss stops the Server. Other child exits remove private tracking and create a later child-exit Signal. |
| `lib/jido/agent_server.ex:2504-2598` | Current error policy permits log-only, stop, maximum-error, error-Signal, and application-function behavior. |
| `lib/jido/agent_server.ex:2874-2955` | Persistent startup loads durable state. Nonpersistent named startup restores `RuntimeStore`. Commits write runtime or durable checkpoints. Clean stop deletes the runtime checkpoint. |
| `lib/jido/agent_server/active_turn.ex:4-130` | One Zoi-backed private ActiveTurn keeps Turn identity, source and effective Signals, caller, task handle, prepared result, versions, and Directive progress. |
| `lib/jido/agent/turn/outcome.ex:1-195` | One public validated Outcome uses five stages, five terminal statuses, complete source/effective Signals, commit fields, and exact Directive counts. |
| `lib/jido/agent_server/plugin_lifecycle.ex:8-232` | Plugin roots start in declaration-derived order, use wrapper supervision, expose restarting state, await readiness, and stay outside Agent state. Init lacks one matching state-version pair. |
| `lib/jido/agent_server/directive_runtime.ex:80-638` | Built-in effects dispatch Signals, start and stop children, preserve relative relationships, and return explicit uncertain remote results. |

No `code_change/4` callback or other public hot Agent Server state-migration
contract exists in current code.

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/agent_server/public_api_test.exs:87-150` | The Server constructs a neutral definition, rejects instance overrides, commits complete state, and invokes one selected executable. |
| `test/jido/agent_server/public_api_test.exs:269-360` | Status stays responsive, sender order uses OTP postponement, reentry fails, and caller timeout does not cancel started work. |
| `test/jido/agent_server/public_api_test.exs:447-568` | Executable cancellation preserves state, indeterminate cancellation stops, current controls are raw, and postponed admission has a finite default. |
| `test/jido/agent_server/startup_test.exs:48-150` | Supervised startup preserves bootstrap failure, rejects dead Registry entries and ignored Plugin starts, validates options, and keeps `start_link` ownership. |
| `test/jido/agent_server/context_test.exs:68-250` | Plugin admission is responsive, cancellable, timed, and separate from state and emitted Signals. |
| `test/jido/agent_server/directive_execution_test.exs:27-131` | Directive validation precedes commit. Commit precedes emitted follow-up work. Runtime-backed Directive work stays responsive. |
| `test/jido/agent_server/directive_execution_test.exs:134-410` | Directive exit and timeout retain commit, record progress, stop later work, apply current error policy, and do not restart stale state. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:32-171` | Jido instance controls and PID ownership are enforced. Exec and Plugin roots belong to the activation and stay outside Agent state. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:174-326` | Readiness gates startup. Plugin replacement reads fresh committed state and stays inspectable. Lifecycle-owner loss restarts from the last runtime checkpoint. |
| `test/jido/agent_server/child_lifecycle_test.exs:59-574` | Child start, address, adoption, parent loss, identity checks, restart, and runtime-only relationships are covered. |
| `test/jido/agent_server/distributed_child_test.exs:11-383` | Explicit known-node child placement preserves identity and uncertainty. It does not prove cluster ownership. |
| `test/jido/agent_server/effect_recovery_test.exs:42-205` | One example capability saves work intent before post-commit delivery and resumes it after loss. This does not make ordinary Directives durable. |
| `test/jido/agent/turn/outcome_test.exs:8-109` | Outcome construction, stage/status consistency, version rules, Directive counts, and timing are validated. |
| `examples/04_runtime/04_09_agent_observation/turn_observation.ex` | Public observation uses current runtime events and Turn Outcome data. |

Skipped research cases and examples are specifications, not proof. This
documentation consolidation did not run runtime tests because no code changed.

## Retained baseline

- `SRV-RB-001`: One `:gen_statem` owns the live Agent and one state version.
- `SRV-RB-002`: At most one Turn, including its ordinary Directive batch, is
  active per Server.
- `SRV-RB-003`: Public PID/name startup, Signal, cancellation, inspection,
  lifecycle, debug, and child-control operations are supported.
- `SRV-RB-004`: Busy Signals use OTP postponement. The configured token limit
  does not bound the process mailbox.
- `SRV-RB-005`: Admission, executable work, and bounded Directive work run
  outside the state-machine process so inspection and control stay responsive.
- `SRV-RB-006`: Direct and live evaluation share Runner preparation and
  finalization. Current route order still differs from the pending target.
- `SRV-RB-007`: Live Directive batch checks and checkpoint success precede
  complete Agent replacement, one version increment, reply, and Directives.
- `SRV-RB-008`: Caller timeout after execution starts does not cancel the Turn.
- `SRV-RB-009`: Admission and execution cancellation preserve committed state.
  Failed cancellation is indeterminate and stops the Server.
- `SRV-RB-010`: Directives run in order after commit. Failure skips later work
  and does not undo the commit.
- `SRV-RB-011`: Named nonpersistent restart restores the latest runtime
  checkpoint. Persistent startup restores durable state.
- `SRV-RB-012`: Plugin runtime generations are owned, readiness-gated,
  restartable, and excluded from Agent state.
- `SRV-RB-013`: Built-in child effects keep runtime handles in Server state and
  report child behavior through later Signals.
- `SRV-RB-014`: Current status maps, Outcome stages and payloads, debug events,
  and open error policies are supported behavior.
- `SRV-RB-015`: No current public contract pins executable code or migrates
  private Server state during a hot code upgrade.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `SRV-GAP-001` | `SRV-REQ-001` to `SRV-REQ-004` | Server module, State, and child-spec code | One-owner and OTP behavior work. Private-state exclusion needs one complete audit. | `Retain`; strengthen evidence |
| `SRV-GAP-002` | `SRV-REQ-005`, `SRV-REQ-006` | Options and public API tests | Canonical construction and instance override rejection work. Definition revision is absent. | `Retain`; recheck after revision migration |
| `SRV-GAP-003` | `SRV-REQ-007` | Public PID/name API and identity design | Handles are replaceable in practice, but no core Ref exists. | `Partial`; additive identity work belongs to seams 03 and 09 |
| `SRV-GAP-004` | `SRV-REQ-008` | Durable restore code and tests | Known active records restore before admission. Ref, tombstone, and revision checks are missing. | `Partial`; consume seam 07 results |
| `SRV-GAP-005` | `SRV-REQ-009` to `SRV-REQ-011` | Startup publishes after Plugin readiness | No revision-zero create occurs. Plugin cleanup exists for current bootstrap failures but lacks initial-write cases. | `Change`; blocked on seam 07 |
| `SRV-GAP-006` | `SRV-REQ-012` to `SRV-REQ-017` | Public API and tests | Sync, cast, request, caller-timeout, and compatibility behavior work. Stable errors and a Ref facade are missing. | `Retain`; staged error and facade additions |
| `SRV-GAP-007` | `SRV-REQ-018` to `SRV-REQ-022` | Postponement code and overload tests | Serialization works. Call overload is a tuple and cast observation is log-only. | `Retain`; normalize observation and errors |
| `SRV-GAP-008` | `SRV-REQ-023` | Reentry code and tests | Reentry is detected, but three different raw controls exist. | `Retain`; align with seam 12 |
| `SRV-GAP-009` | `SRV-REQ-024` to `SRV-REQ-027` | Admission, Runner, and Exec code | Current admission can alter the command before route selection. The pending Turn target selects first from source. | `Conflict`; change with seams 04 and 05 |
| `SRV-GAP-010` | `SRV-REQ-028`, `SRV-REQ-029` | Admission reuses Directive timeout; native Exec has no Server timer | No whole-Turn limit or complete late-result proof exists. | `Missing`; approve exact task and timer boundary |
| `SRV-GAP-011` | `SRV-REQ-030`, `SRV-REQ-031` | Cancellation code and tests | Pre-commit cancellation works. Results differ from seam-12 codes, and commit has no explicit externally visible stage. | `Partial`; normalize and add race proof |
| `SRV-GAP-012` | `SRV-REQ-032` to `SRV-REQ-038` | Finalization, validation, commit, and Directive tests | Candidate, batch, checkpoint, replacement, version, reply, and no-Directive rules substantially work. | `Retain`; add complete order matrix |
| `SRV-GAP-013` | `SRV-REQ-039` | Persistence failure branch | Only uncertain writes always stop. Confirmed conflicts can continue. | `Conflict`; approve all-write-error authority loss |
| `SRV-GAP-014` | `SRV-REQ-040` | RuntimeCheckpoint and lifecycle tests | Same-instance abnormal restart restores the last commit and version. | `Proven` |
| `SRV-GAP-015` | `SRV-REQ-041` | Plugin lifecycle and readiness tests | Ownership and readiness work for the mixed Plugin behavior. | `Proven` for current behavior; facet migration is `Partial` |
| `SRV-GAP-016` | `SRV-REQ-042` | Plugin Init and replacement tests | Replacement reads fresh state, but state and version are not one immutable input. | `Missing`; blocked on seam 05 value contract |
| `SRV-GAP-017` | `SRV-REQ-043` to `SRV-REQ-045` | Runtime replacement and readiness tests | Inspection stays responsive and failed readiness stops. Required-runtime fallback denial needs facet proof. | `Partial` |
| `SRV-GAP-018` | `SRV-REQ-046` | Scheduler and recoverable-effect tests | Built-in runtimes use later Signals. No owner-facet conformance test covers all runtimes. | `Partial`; retain rule |
| `SRV-GAP-019` | `SRV-REQ-047` to `SRV-REQ-049` | Directive state machine and tests | Ordered fail-fast settlement and commit retention work. | `Proven` |
| `SRV-GAP-020` | `SRV-REQ-050` to `SRV-REQ-052` | DirectiveRuntime and child tests | Runtime-only tracking, later child Signals, and remote uncertainty work for current APIs. | `Proven`; keep topology claims excluded |
| `SRV-GAP-021` | `SRV-REQ-053`, `SRV-REQ-059` | Checkpoints omit Directive batch | There is no replay path, but no focused crash-during-batch test proves non-replay and no reconstructed Outcome. | `Missing` evidence |
| `SRV-GAP-022` | `SRV-REQ-054`, `SRV-REQ-055` | Hibernate code and idle tests | Hibernation waits for idle and preserves current active state. Tombstone-aware lifecycle remains pending. | `Proven` for current records; target is `Partial` |
| `SRV-GAP-023` | `SRV-REQ-056`, `SRV-REQ-057` | Termination code and runtime fault tests | Owned tasks are stopped and several invariant faults exit. Fault classification is incomplete. | `Partial`; align with seam 12 |
| `SRV-GAP-024` | `SRV-REQ-058` | ActiveTurn, Outcome, and tests | One observed terminal Outcome is validated. A Server crash can interrupt publication. | `Proven` at observed terminal points |
| `SRV-GAP-025` | `SRV-REQ-060` | Current restore and definition-revision research case | Module and ID checks exist. Definition revision does not. | `Blocked` on seams 01, 02, and 07 |
| `SRV-GAP-026` | `SRV-REQ-061` | Runner and `Jido.Exec` invocation | The exact selected executable is invoked. No loaded-code pin exists. | `Proven` for current non-pinning model |
| `SRV-GAP-027` | `SRV-REQ-062` to `SRV-REQ-065` | Module boundaries and public APIs | Current code mostly respects these limits, but stable Ref, external public-only fixture, and owner-facet split are absent. | `Partial`; keep limits and close cross-package evidence |
| `SRV-GAP-028` | Hot private-state upgrade | No `code_change/4` or migration tests | The old proposal implied code revision behavior without a state migration contract. | `Deferred`; separate design required |

## Dispositions of superseded claims

This table preserves or resolves every distinct claim from the replaced Agent
Server proposal and gap report. Git history retains their exact text.

| Superseded claim or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Agent Server must be internal and application code must use only a Ref-first facade. | `Replace`. | Ref facade is additive and instance-owned. Package and identity prerequisites keep current PID/name APIs until later approval. |
| Only `start_link` and child specification can remain public. | `Remove`. | Current command, control, inspection, debug, child, and lifecycle operations are documented and tested. |
| A Server owns one committed Agent, version, mailbox, active Turn, persistence coordination, Plugin links, attachments, and effect control. | `Retain`. | These are current seam-owned roles. |
| The private state must contain `initial_agent` and reset nonpersistent restart to it. | `Remove`. | Current and prerequisite targets retain the last committed in-instance runtime checkpoint. |
| A persistent child specification keeps only Ref and instance as restart source. | `Defer`. | Core Ref and namespace binding do not exist. Seam 09 owns restart source configuration. |
| Runtime handles never enter Agent or checkpoint data. | `Retain`. | Current state, checkpoint, and child tests support this invariant. |
| The runtime has exactly four phases and no `admitting` phase. | `Replace`. | Current public status exposes five total phases. Keep them for compatibility. |
| Plugin preparation must be hidden inside `running`. | `Remove as a phase rule`. | `admitting` is current public data. Seam 04 owns evaluator stages, not Server phases. |
| Persistent creation starts provisional runtimes, waits, writes revision zero, and then publishes. | `Retain target`. | Plugin readiness exists; initial create is missing and belongs jointly to seams 07 and 08. |
| Recovery workers can resume pending work while later Turns continue. | `Retain as capability behavior`. | Explicit capability state can do this. Ordinary Directives receive no replay guarantee. |
| One public control model must expose only `evaluate`, `commit`, and `directive`. | `Replace`. | Current Outcomes use five supported stages. Keep them until seam 13 approves migration. |
| `turn_timeout` covers route, preparation, execution, contribution, and validation. | `Retain target with correction`. | Live admission also belongs in the cancellable Server-wide limit. Exact option and task shape remain open. |
| Mailbox wait is outside the Turn limit. | `Retain`. | Caller admission deadline covers postponed time. The Server limit starts with active work. |
| Cancellation terminates the task, waits for `DOWN`, rejects late results, and preserves state. | `Retain target`. | Current task forms differ. The acceptance test must prove both race orders. |
| Persistence timeout is an indeterminate write and stops authority. | `Retain conditionally`. | Seam 07 deferred the option. If configured by owning seams, the result meaning is indeterminate. |
| Directive timeout is post-commit failure and creates no replay duty. | `Retain`. | Current commit retention works. Effect completion can remain uncertain. |
| Cancellation and completion races are decided by the first processed event. | `Retain target`. | `:gen_statem` serialization supports the model, but deterministic boundary tests are incomplete. |
| The facade must expose a fixed list of Ref-first command and lifecycle functions. | `Defer exact facade`. | Seam 09 owns names, namespace binding, resolution, and public lifecycle policy. |
| `start_agent` and `activate_agent` must define complete startup semantics here. | `Split ownership`. | This seam owns Server readiness. Seam 09 owns facade and publication. Seam 07 owns record meaning. |
| Public runtime options include partition, Turn, readiness, Directive, dispatch, error, idle, and postponed limits. | `Retain roles; defer exact surface`. | Current options exist except whole-Turn and persistence limits. Instance-owned fields stay outside this seam. |
| Error policy must become only closed `continue` or `stop` data. | `Replace with staged compatibility`. | Current Signal, maximum-count, and function policies are supported. They cannot override safety invariants. |
| Controlled policy stop must not restart a transient child. | `Retain`. | Current shutdown normalization and tests prove this behavior. |
| `call` success proves commit but not Directive completion. | `Retain`. | This matches current code and seam 06. |
| `cast :ok` confirms only message send and can later be dropped. | `Retain`. | This is current documented behavior. |
| OTP asynchronous request envelopes must stay standard. | `Retain`. | Seam 12 registers this protocol. |
| Caller timeout after start does not cancel the Turn. | `Retain`. | Current test evidence proves it. |
| Stable cancellation results must be `turn_cancelled`, `no_active_turn`, `turn_mismatch`, and `too_late`. | `Retain target; migrate`. | Current atoms differ. Seam 12 owns error shape and codes. |
| Same-Agent synchronous reentry must fail. | `Retain`. | Current code covers admission, executable, and Directive process trees. |
| Every persistence write error must stop with lost write authority. | `Retain target, blocked`. | Current confirmed failures can continue. Seams 06, 07, 08, and 12 must change together. |
| Framework invariant failure must crash and use the configured restart source. | `Retain`. | Fault classification and recovery proof must be complete. |
| Plugin replacement must receive matching state and state version. | `Retain target`. | Current restart reads fresh state but lacks one coherent input. |
| Directive failure has fixed stop behavior. | `Remove`. | Current error policy can continue or stop. Only commit retention and batch stop are fixed. |
| Directive failure follows error policy. | `Retain with limit`. | Policy cannot undo commit, resume skipped Directives, or override write authority. |
| New `Agent.Status`, `Turn.Status`, and `Agent.Commit` structs must replace maps and snapshot. | `Remove as current target`. | Seam 12 says a struct needs proved value. Keep documented maps during migration. |
| Status must expose only four phases and three active stages. | `Remove`. | It conflicts with supported current status. Seam 13 can propose a versioned projection. |
| Outcome must contain only identities and counts, never complete Signals. | `Defer`. | Current public Outcome contains Signals. Seam 13 owns data minimization and compatibility. |
| Outcome is the terminal value for observed live work. | `Retain`. | Current schema and tests prove terminal consistency when publication occurs. |
| No per-Server debug timeline exists. | `Remove`. | A bounded public debug path exists and package prerequisites preserve it. |
| Domain output is committed Agent, external work is Directive, and observation is bounded runtime data. | `Retain`. | This matches the Bright Line when current debug and Outcome compatibility are stated. |
| Definition revision can pin executable code. | `Remove for V3`. | Seam 04 recommends using code loaded when `Jido.Exec` invokes the selected executable. |
| Agent Server owns Ref resolution, namespace binding, placement, or cluster authority. | `Reject`. | Seams 03, 09, 10, and external cluster owners own these policies. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the formal plan only after the user approves this seam.

### Phase 0 — Resolve prerequisites and Server decisions

- Requirements: all `SRV-REQ` identifiers.
- Required outcome: approved API compatibility, phase, Turn-limit,
  write-authority, Plugin degradation, error-policy, and code-revision choices.
- Constraints: do not treat any pending prerequisite as approved and do not
  define instance or topology policy.
- Compatibility: no runtime change.
- Verification: review all `SRV-DEC` items and blocker resolutions.
- Exit criteria: one non-conflicting target exists across seams 03 through 09,
  12, and 13.

### Phase 1 — Freeze the retained live runtime contract

- Requirements: `SRV-REQ-001` to `SRV-REQ-004`, `SRV-REQ-012` to
  `SRV-REQ-023`, `SRV-REQ-032` to `SRV-REQ-038`, and `SRV-REQ-047` to
  `SRV-REQ-059` where current evidence is proven.
- Required outcome: public documentation and tests state current OTP,
  serialization, commit, Directive, child, lifecycle, status, Outcome, and
  compatibility meanings without contradictory proposals.
- Constraints: keep current APIs and keep candidate and storage semantics in
  their owner seams.
- Compatibility: no removal or silent result change.
- Verification: focused characterization tests and a public contract inventory.
- Exit criteria: each retained behavior has direct evidence and one owner.

### Phase 2 — Align source-Signal execution and Turn control

- Requirements: `SRV-REQ-024` to `SRV-REQ-031` and `SRV-REQ-061`.
- Required outcome: admission cannot change selection, one Server-wide
  pre-commit limit exists, cancellation and late results have one boundary,
  and the exact selected executable reaches `Jido.Exec`.
- Constraints: seam 04 owns candidate semantics; the Server owns tasks, timers,
  cancellation, and stale-result authority.
- Compatibility: migrate route-changing Plugins with seam 05. Keep caller wait
  and current PID call forms.
- Verification: admission-order, Action, Flow, timeout, cancellation-race,
  caller-timeout, and stale-result tests.
- Exit criteria: every pre-commit event has one state, reply, timer, and Outcome.

### Phase 3 — Establish durable startup and write authority

- Requirements: `SRV-REQ-008` to `SRV-REQ-011`, `SRV-REQ-035`, and
  `SRV-REQ-038` to `SRV-REQ-040`, plus `SRV-REQ-060` when revision exists.
- Required outcome: validated restore, revision-zero create, publication after
  confirmed write, all-error authority loss, and explicit reactivation.
- Constraints: seam 07 owns records, keys, CAS classifications, and tombstones.
- Compatibility: change public errors and restart behavior with seams 07, 09,
  and 12 as one rollout.
- Verification: restore modes, initial conflict, initial indeterminate result,
  provisional cleanup, every write result, no-Directive, stop-before-next-Turn,
  and explicit restore tests.
- Exit criteria: no active writer continues after a non-confirmed required
  persistent write.

### Phase 4 — Align Plugin facets and coherent replacement

- Requirements: `SRV-REQ-041` to `SRV-REQ-046`.
- Required outcome: Agent Server facet runtime ownership, one committed
  state-version bootstrap pair, responsive replacement visibility, no fallback,
  and stop on failed readiness.
- Constraints: seam 05 owns facet values and callbacks. Runtime handles remain
  private. State changes return as Signals.
- Compatibility: keep current Plugin declarations and state-pull behavior until
  the bootstrap input passes parity tests.
- Verification: first start, restart during idle and active phases, commit
  race, readiness failure, timeout, missing runtime, and later-Signal tests.
- Exit criteria: every runtime generation starts from one coherent committed
  view.

### Phase 5 — Close ownership, migration, and release evidence

- Requirements: all approved `SRV-REQ` identifiers.
- Required outcome: the Ref-first instance facade can use this boundary without
  private access, observation uses the approved compatibility values, and no
  Server contract decides placement or cluster authority.
- Compatibility: no PID/name, map, Outcome, debug, or error-policy removal
  without its separate approved gate.
- Verification: public-only package fixture, full Jido tests, cross-package V3
  matrix, docs, types, format, compile, lint, and coverage.
- Exit criteria: the acceptance matrix has no `Missing`, `Conflict`, or
  `Blocked` entry for an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `SRV-REQ-001` to `SRV-REQ-004` | Server State, OTP startup, and ownership tests | Complete private-handle exclusion and one-owner audit | `Proven` |
| `SRV-REQ-005`, `SRV-REQ-006` | Options and public API construction tests | Repeat with definition revision and all supported authoring forms | `Proven` for current forms; target is `Partial` |
| `SRV-REQ-007` | PID/name lookup and replacement behavior | Ref-to-handle replacement test through seam 09 | `Partial` |
| `SRV-REQ-008` | Current active-record restore tests | Ref, tombstone, definition revision, and old-record matrix | `Partial` |
| `SRV-REQ-009` to `SRV-REQ-011` | Plugin readiness precedes publication | Revision-zero create, duplicate, fault, timeout, and cleanup tests | `Missing` |
| `SRV-REQ-012` to `SRV-REQ-017` | Public API, async request, and caller-timeout tests | Stable seam-12 errors and additive Ref-facade integration | `Proven` for current controls; target migration is `Partial` |
| `SRV-REQ-018` to `SRV-REQ-022` | Postponement and overload tests | Stable call error and bounded cast observation | `Partial` |
| `SRV-REQ-023` | Reentry tests for executable and Directive; admission code | Stable error matrix for all three process trees | `Partial` |
| `SRV-REQ-024` to `SRV-REQ-027` | Current admission and Exec path | Source-before-admission selection and route-changing Plugin tests | `Conflict` |
| `SRV-REQ-028`, `SRV-REQ-029` | No complete Server Turn limit | Whole-unit timer, task termination, `DOWN`, late-result, state, and Outcome test | `Missing` |
| `SRV-REQ-030`, `SRV-REQ-031` | Admission and execution cancellation tests | Stable errors and deterministic cancel/result race in both orders | `Partial` |
| `SRV-REQ-032` to `SRV-REQ-038` | Candidate, Directive, persistence, equal-state, reply, and order tests | One requirement-mapped commit-order matrix | `Proven` |
| `SRV-REQ-039` | Indeterminate stop; confirmed-conflict continuation | Every CAS failure stops before new evaluation | `Conflict` |
| `SRV-REQ-040` | Runtime lifecycle restart test | Keep after identity and checkpoint migration | `Proven` |
| `SRV-REQ-041` | Plugin start, ownership, and readiness tests | Agent Server facet parity test | `Proven` for current mixed behavior; target is `Partial` |
| `SRV-REQ-042` | Fresh-state replacement tests | Atomic state-version input and commit-race cases | `Missing` |
| `SRV-REQ-043` to `SRV-REQ-045` | Restart visibility and readiness failure tests | Required-runtime fallback denial through facet API | `Partial` |
| `SRV-REQ-046` | Scheduler and effect-recovery Signals | Public-only Plugin runtime conformance case | `Partial` |
| `SRV-REQ-047` to `SRV-REQ-049` | Directive order, failure, timeout, and commit tests | Keep through facet and error migration | `Proven` |
| `SRV-REQ-050` to `SRV-REQ-052` | Child lifecycle and distributed child tests | Keep exact uncertainty without adding topology authority | `Proven` |
| `SRV-REQ-053` | Checkpoint shapes contain no batch | Crash during each Directive position and prove no replay | `Missing` |
| `SRV-REQ-054`, `SRV-REQ-055` | Hibernate and idle-lifecycle tests | Repeat with active/tombstone target records | `Proven` for current record; target is `Partial` |
| `SRV-REQ-056`, `SRV-REQ-057` | Termination and runtime-boundary tests | Full owned-work cleanup and invariant/application-fault classification | `Partial` |
| `SRV-REQ-058` | Outcome schema and runtime tests | Keep after final error and observation projection | `Proven` |
| `SRV-REQ-059` | No reconstructed settlement code | Crash-before-publication and restart observation test | `Missing` |
| `SRV-REQ-060` | Module/ID checks only | Definition match, mismatch, missing legacy revision, and no-readiness tests | `Blocked` |
| `SRV-REQ-061` | Exact executable reaches `Jido.Exec` | Loaded-code non-pinning documentation and controlled code-reload test | `Partial` |
| `SRV-REQ-062` to `SRV-REQ-064` | Current package and module boundaries | Architecture checks after Ref, facet, and persistence changes | `Partial` |
| `SRV-REQ-065` | Public functions exist; no public-only external fixture | External package that uses only documented functions and no private messages | `Missing` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| PID and name API | Keep all documented current operations. Add Ref-first instance calls before any later restriction. |
| Startup | Keep module, neutral definition, and Agent instance inputs. Add revision and initial-write checks without changing canonical construction ownership. |
| Identity | Keep IDs and term-valued partitions. Do not require Ref until seams 03 and 09 define namespace and conversion. |
| Status | Keep the current map and five phase atoms. Add fields only through an owner-documented compatible form. |
| Snapshot and Outcome | Keep the snapshot map and current validated Outcome. Seam 13 must inventory consumers before changing fields, Signals, or stages. |
| Debug | Keep bounded `set_debug` and `recent_events`. A later removal needs observation replacement proof and security review. |
| Error controls | Convert one public boundary at a time through seam 12. Keep OTP request envelopes and best-effort cast `:ok`. |
| Error policy | Keep current policy forms until a separate deprecation. Make persistence authority, commit retention, and batch stop non-overridable first. |
| Routing and Plugins | Change fixed source selection and facet callbacks as one compatible unit. Do not strand a Plugin that changes routes under the old contract. |
| Turn limit | Add the Server limit without reusing caller wait, Directive timeout, or lower `Jido.Exec` option meanings. |
| Persistence | Roll out initial create, CAS classification, authority stop, public errors, and activation recovery together. Keep legacy records readable. |
| Runtime checkpoints | Keep same-instance abnormal-restart recovery. Clean instance stop continues to remove nondurable checkpoints. |
| Plugin runtime Init | Add state and version while current state-pull APIs remain. Do not reuse a prior generation's Init. |
| Children | Keep owned-child and explicit known-node behavior. No Ref, transport, placement, or cluster claim is implied. |
| Ordinary Directives | Keep transient non-replay behavior. Recoverable capabilities retain their separate intent and acknowledgement contracts. |
| Code revision | Add definition revision as restore data. Do not claim code pinning or hot private-state migration. |

Rollback must restore route order and Plugin callback compatibility together.
It must also restore persistence result handling, caller errors, and activation
restart behavior as one unit. Older code must not silently run as an
authoritative writer against a record format that it cannot interpret.

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `SRV-BLK-001` | `Blocker` | 00 Overview | One-owner, stable identity, durability, cancellation, and compatibility targets are pending approval. | Approve them or replace them with explicit Server assumptions. |
| `SRV-BLK-002` | `Blocker` | 90 Package boundaries | Local-core ownership, API retention, and public-only extension rules are pending. | Approve or change the package boundary. |
| `SRV-BLK-003` | `Blocker` | 12 Errors and contracts | Stable timeout, overload, reentry, cancellation, runtime, and persistence errors are pending. | Approve the result registry before public conversion. |
| `SRV-BLK-004` | `Blocker` | 01 Agent and 02 Agent authoring | Definition revision and canonical versioned construction are not implemented. | Approve revision defaults and old-definition rules. |
| `SRV-BLK-005` | `Blocker` | 03 Agent identity and 09 Jido instance | Core Ref, namespace binding, partition conversion, and Ref-first facade do not exist. | Approve identity and instance resolution without removing current handles. |
| `SRV-BLK-006` | `Blocker` | 04 Turn evaluation and 05 Plugins | Current Plugin admission and preparation can affect the Signal before route selection. | Approve and migrate fixed source-Signal selection with facet compatibility. |
| `SRV-BLK-007` | `Blocker` | 06 Commit, 07 Persistence, 08 Agent Server | Current confirmed write errors can continue, contrary to the pending all-error target. | Select one authority rule and align stop, caller, and restore behavior. |
| `SRV-BLK-008` | `Blocker` | 07 Persistence | No revision-zero create, tombstone-aware restore, or complete CAS result set exists. | Approve record lifecycle and mixed-version rules. |
| `SRV-BLK-009` | `Blocker` | 05 Plugins | No approved runtime bootstrap value contains matching owned state and state version. | Approve its fields, identity, and restart-race behavior. |
| `SRV-BLK-010` | `Assumption` | 08 Agent Server | A Server-wide Turn limit starts with active pre-commit work, not mailbox wait, and ends when commit begins. | Approve or change `SRV-DEC-003`. |
| `SRV-BLK-011` | `Assumption` | 08 Agent Server and 13 Observability | Current status, Outcome, and debug contracts remain during migration. | Inventory consumers before a versioned replacement. |
| `SRV-BLK-012` | `Assumption` | 10 Runtime topology | Explicit known-node child operations remain supported but grant no cluster authority. | Keep placement and authority outside this seam. |
| `SRV-BLK-013` | `Blocker` | 04 Turn evaluation and `jido_action` | Definition revision does not pin loaded Action or Flow code. | Approve the V3 non-guarantee or create a lower-owner code-revision contract. |
| `SRV-BLK-014` | `Blocker` | 08 Agent Server | No public need, state migration, in-flight-Turn, rollback, or test contract exists for `code_change/4`. | Defer hot private-state upgrade or approve a separate design. |
| `SRV-BLK-015` | `Blocker` | Design index and dependent seam owners | The main design review table and seam 09 still name the removed legacy Server files, but this task permits edits only in this seam. | Update the out-of-scope links in separately authorized edits. |

## Completion criteria

- [ ] The user has approved or changed every `SRV-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `SRV-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict`, `Missing`, or `Blocked` entry remains for an
      approved requirement.
- [ ] Source-Signal selection, whole-Turn timeout, cancellation race, and late
      result behavior have deterministic tests.
- [ ] Initial durable create and every persistence result have one publication,
      state, Directive, authority, caller, and restart result.
- [ ] Every Plugin runtime generation receives matching committed state and
      version.
- [ ] Ordinary Directive interruption has non-replay and no-reconstructed-
      settlement proof.
- [ ] Current API, status, Outcome, debug, error-policy, and child behavior
      remain supported until their separate migration gates pass.
- [ ] No Agent Server requirement defines Ref fields, namespace binding,
      instance publication policy, placement, transport, or cluster authority.
- [ ] Public module docs, types, dependent seams, and the main design index use
      the approved contract.
- [ ] After approval, a separate formal implementation plan defines tasks.
