> Seam alignment evidence. The implementation direction was selected on
> 2026-09-10. Seam 09 now supplies the Ref-first instance controls.

# Agent Server alignment

## Status

- Implementation reviewed: 2026-09-10 on branch `v3-spike`.
- Prerequisites: package boundaries, stable Agent identity values, fixed
  source-Signal evaluation, owner-specific Plugin facets, commit authority,
  durable record lifecycle, Agent definition versions, and current public
  error contracts are present.
- Alignment state: `Implemented; Ref-first instance integration is also complete`.

The Agent Server now has one active pre-commit timeout, strict ready
publication, and coherent Plugin runtime bootstrap values. Existing
PID-and-name controls, status maps, Outcomes, error policies, and debug paths
remain compatible. Seam 09 owns Ref resolution and the additive instance
facade. Seam 13 owns any later observation projection.

This execution state is not approval of every requirement in the target
design.

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
- [Errors design](../12_errors-and-contracts/design.md): supplies stable Plugin
  and Exec conversion codes and registers current overload, reentry,
  cancellation, persistence, and OTP controls. Seam 08 owns any later
  lifecycle conversion.
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
  CAS results, tombstones, restore meaning, and the implemented all-write-error
  authority rule.
- [Target design](design.md): defines this seam's recommended runtime contract.

### Canonical code

| Evidence | Canonical current behavior |
| --- | --- |
| `lib/jido/agent_server.ex:1-47,432-500` | `Jido.AgentServer` is a `:gen_statem`. It owns one live Agent, state version, active Turn, runtime work, and five total phases including initialization. |
| `lib/jido/agent_server.ex:85-430` | Public PID/name operations include startup, call, cast, request, inspection, cancellation, debug, lookup, child controls, snapshot, and hibernation. |
| `lib/jido/agent_server/options.ex` | One Zoi-backed option value validates Agent construction, registration, persistence, limits, executable runtime, lifecycle, and open error policies. `turn_timeout` is a distinct pre-commit limit. |
| `lib/jido/agent_server.ex` startup path | Startup reserves the Registry identity, restores and validates, starts Plugin roots, waits for readiness, confirms revision-zero creation when required, and then publishes `:ready`. |
| `lib/jido/agent_server.ex:579-620,1878-1924` | Inspection remains responsive in every phase. Status and snapshot are protocol maps, not target-specific public structs. |
| `lib/jido/agent_server.ex:759-848,1926-1978` | Busy Signals use OTP postponement. A token set bounds only events already seen by the state machine. Full calls fail; full casts are dropped. |
| `lib/jido/agent_server.ex:709-756,1596-1637` | Admission and executable work can be cancelled. Current controls are atoms such as `:idle`, `:directing`, `:stale_turn`, and `:cancelled`. |
| `lib/jido/agent_server.ex` Turn path | One ActiveTurn starts before live admission. One Server timer covers admission and candidate evaluation until commit begins. Owned admission and executable work are cancelled on timeout. |
| `lib/jido/agent_server.ex:1469-1545` | Runner finalization and live Directive validation precede checkpoint work. A successful commit writes first, replaces the complete Agent, increments one version, replies, and then starts Directives. |
| `lib/jido/agent_server.ex:1582-1617` | Every required persistence write failure returns the failure and stops the activation before it can evaluate more work. |
| `lib/jido/agent_server.ex:1639-1862` | Directives run in list order after commit. One failure stops the batch. Process-backed work has one Directive timeout and does not roll back state. |
| `lib/jido/agent_server.ex:1981-2008` | Synchronous reentry from admission, executable, and Directive process trees is detected and rejected. |
| `lib/jido/agent_server.ex:2148-2218` | Plugin lifecycle-owner loss stops the Server. Other child exits remove private tracking and create a later child-exit Signal. |
| `lib/jido/agent_server.ex:2504-2598` | Current error policy permits log-only, stop, maximum-error, error-Signal, and application-function behavior. |
| `lib/jido/agent_server.ex:2874-2955` | Persistent startup loads durable state. Nonpersistent named startup restores `RuntimeStore`. Commits write runtime or durable checkpoints. Clean stop deletes the runtime checkpoint. |
| `lib/jido/agent_server/active_turn.ex` | One Zoi-backed private ActiveTurn keeps Turn identity, source and effective Signals, caller, task handle, prepared result, versions, Directive progress, and the pre-commit deadline. |
| `lib/jido/agent/turn/outcome.ex:1-195` | One public validated Outcome uses five stages, five terminal statuses, complete source/effective Signals, commit fields, and exact Directive counts. |
| `lib/jido/agent_server/plugin_lifecycle.ex` and `plugin_child.ex` | Plugin roots start in declaration order, use wrapper supervision, expose restarting state, await readiness, and stay outside Agent state. Every generation gets a newly built owned-state and state-version pair. |
| `lib/jido/agent_server/directive_runtime.ex:80-638` | Built-in effects dispatch Signals, start and stop children, preserve relative relationships, and return explicit uncertain remote results. |

No `code_change/4` callback or other public hot Agent Server state-migration
contract exists in current code.

### Tests and examples

| Evidence | Behavior proved or specified |
| --- | --- |
| `test/jido/agent_server/public_api_test.exs:87-150` | The Server constructs a neutral definition, rejects instance overrides, commits complete state, and invokes one selected executable. |
| `test/jido/agent_server/public_api_test.exs:269-360` | Status stays responsive, sender order uses OTP postponement, reentry fails, and caller timeout does not cancel started work. |
| `test/jido/agent_server/public_api_test.exs` | Executable cancellation preserves state, completion and cancellation races use first processed event, pre-commit timeout stops owned work and rejects late results, and current controls remain compatible. |
| `test/jido/agent_server/startup_test.exs:48-150` | Supervised startup preserves bootstrap failure, rejects dead Registry entries and ignored Plugin starts, validates options, and keeps `start_link` ownership. |
| `test/jido/agent_server/context_test.exs` | Plugin admission is responsive, cancellable, covered by the same Turn timeout, and separate from state and emitted Signals. |
| `test/jido/agent_server/directive_execution_test.exs:27-131` | Directive validation precedes commit. Commit precedes emitted follow-up work. Runtime-backed Directive work stays responsive. |
| `test/jido/agent_server/directive_execution_test.exs:134-410` | Directive exit and timeout retain commit, record progress, stop later work, apply current error policy, and do not restart stale state. |
| `test/jido/agent_server/runtime_lifecycle_test.exs:32-171` | Jido instance controls and PID ownership are enforced. Exec and Plugin roots belong to the activation and stay outside Agent state. |
| `test/jido/agent_server/plugin_lifecycle_test.exs` | Readiness gates startup, public instance lookup hides `:starting` entries, replacement stays inspectable, and readiness failure stops the activation. |
| `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs` | A split Agent and Agent Server Plugin package rebuilds a resource from matching committed owned state and state version. The public state-pull path still reconciles later commits. |
| `test/jido/agent_server/child_lifecycle_test.exs:59-574` | Child start, address, adoption, parent loss, identity checks, restart, and runtime-only relationships are covered. |
| `test/jido/agent_server/distributed_child_test.exs:11-383` | Explicit known-node child placement preserves identity and uncertainty. It does not prove cluster ownership. |
| `test/jido/agent_server/commit_boundary_test.exs` | Crashes at the first and second ordinary Directive positions do not replay a batch or reconstruct the prior activation's Outcome. |
| `test/jido/agent_server/effect_recovery_test.exs:42-205` | One explicit capability saves work intent before post-commit delivery and resumes it after loss. This does not make ordinary Directives durable. |
| `test/jido/agent/turn/outcome_test.exs:8-109` | Outcome construction, stage/status consistency, version rules, Directive counts, and timing are validated. |
| `examples/04_runtime/04_09_agent_observation/turn_observation.ex` | Public observation uses current runtime events and Turn Outcome data. |

The FA-06 research checks are enabled and passing. Focused Server, Plugin,
persistence, error, and example suites pass with the selected behavior.

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
  finalization. Live selection uses the unchanged source Signal.
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
  restartable, excluded from Agent state, and built from one committed owned-
  state and state-version pair.
- `SRV-RB-013`: Built-in child effects keep runtime handles in Server state and
  report child behavior through later Signals.
- `SRV-RB-014`: Current status maps, Outcome stages and payloads, debug events,
  and open error policies are supported behavior.
- `SRV-RB-015`: No current public contract pins executable code or migrates
  private Server state during a hot code upgrade.

## Gap register

This register records the state after implementation.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `SRV-GAP-001` | `SRV-REQ-001` to `SRV-REQ-004` | Server State, OTP startup, checkpoint, and child tests | Private handles remain only in Server-owned values. | `Resolved` |
| `SRV-GAP-002` | `SRV-REQ-005`, `SRV-REQ-006` | Options, construction, and definition-version tests | Canonical construction and instance protection are implemented. | `Resolved` |
| `SRV-GAP-003` | `SRV-REQ-007` | Stable Ref value, seam-09 local resolution, and public PID/name API | The instance facade resolves the replaceable PID before it calls this Server. | `Resolved across seams 08 and 09` |
| `SRV-GAP-004` | `SRV-REQ-008` | Durable lifecycle, definition checks, stable Ref keys, and namespace rebind proof | The instance supplies namespace while the Server retains activation meaning. | `Resolved across seams 07 to 09` |
| `SRV-GAP-005` | `SRV-REQ-009` to `SRV-REQ-011` | Initial-write cleanup and publication test | Registry identity is reserved as `:starting`; public lookup accepts only `:ready` after confirmed creation. | `Resolved` |
| `SRV-GAP-006` | `SRV-REQ-012` to `SRV-REQ-017` | Public API, caller-timeout, and Ref-facade tests | Current PID/name and OTP controls remain supported beside additive Ref delegates. | `Resolved` |
| `SRV-GAP-007` | `SRV-REQ-018` to `SRV-REQ-022` | Postponement and overload tests | OTP order, bounded reached-event tokens, call rejection, and bounded cast observation remain supported. | `Resolved` |
| `SRV-GAP-008` | `SRV-REQ-023` | Reentry tests | Admission, executable, and Directive process trees are rejected through owner-defined controls. | `Resolved` |
| `SRV-GAP-009` | `SRV-REQ-024` to `SRV-REQ-027` | Seam-04 Runner and seam-05 owner facets | Admission cannot change source selection; the selected executable reaches Exec. | `Resolved` |
| `SRV-GAP-010` | `SRV-REQ-028`, `SRV-REQ-029` | ActiveTurn timer and admission/execution tests | One `turn_timeout` covers active pre-commit work, cancels owned work, preserves state, and rejects late messages. | `Resolved` |
| `SRV-GAP-011` | `SRV-REQ-030`, `SRV-REQ-031` | Deterministic cancel-first and completion-first tests | First processed event decides the race. Directing and settled Turns reject cancellation. | `Resolved` |
| `SRV-GAP-012` | `SRV-REQ-032` to `SRV-REQ-038` | Commit boundary and persistence tests | Validation, checkpoint, replacement, version, reply, and Directive order are proved. | `Resolved` |
| `SRV-GAP-013` | `SRV-REQ-039` | Persistence failure matrix | Every non-confirmed required write stops the activation. | `Resolved` |
| `SRV-GAP-014` | `SRV-REQ-040` | RuntimeCheckpoint and lifecycle tests | Same-instance abnormal restart restores the last commit and version. | `Proven` |
| `SRV-GAP-015` | `SRV-REQ-041` | Split-facet runtime example and lifecycle tests | The Agent Server facet owns runtime callbacks and one runtime root. | `Resolved` |
| `SRV-GAP-016` | `SRV-REQ-042` | `Jido.Plugin.Init` and FA-06 | First start and replacement receive one immutable owned-state and state-version pair. | `Resolved` |
| `SRV-GAP-017` | `SRV-REQ-043` to `SRV-REQ-045` | Runtime restart, visibility, and readiness tests | Inspection stays responsive, no process-free fallback exists, and failed readiness stops the activation. | `Resolved` |
| `SRV-GAP-018` | `SRV-REQ-046` | Split-facet runtime and recoverable capability tests | Runtime state changes return through later Signals and commits. | `Resolved` |
| `SRV-GAP-019` | `SRV-REQ-047` to `SRV-REQ-049` | Directive state machine and tests | Ordered fail-fast settlement and commit retention work. | `Proven` |
| `SRV-GAP-020` | `SRV-REQ-050` to `SRV-REQ-052` | DirectiveRuntime and child tests | Runtime-only tracking, later child Signals, and remote uncertainty work for current APIs. | `Proven`; keep topology claims excluded |
| `SRV-GAP-021` | `SRV-REQ-053`, `SRV-REQ-059` | Crash-at-index commit-boundary tests | Ordinary batches are not replayed and a new activation has no reconstructed Outcome. | `Resolved` |
| `SRV-GAP-022` | `SRV-REQ-054`, `SRV-REQ-055` | Hibernate, idle, and tombstone tests | Hibernation waits for idle and durable lifecycle meanings stay separate. | `Resolved` |
| `SRV-GAP-023` | `SRV-REQ-056`, `SRV-REQ-057` | Termination and runtime-boundary tests | Owned work stops with the activation; invalid internal results fail closed. | `Resolved` |
| `SRV-GAP-024` | `SRV-REQ-058` | ActiveTurn, Outcome, and tests | One observed terminal Outcome is validated. A Server crash can interrupt publication. | `Proven` at observed terminal points |
| `SRV-GAP-025` | `SRV-REQ-060` | Record definition-version matrix | Definition mismatch fails before Plugin startup and readiness. | `Resolved` |
| `SRV-GAP-026` | `SRV-REQ-061` | Runner and Exec boundary tests | The exact selected executable is invoked with loaded code; no code pin is claimed. | `Resolved` |
| `SRV-GAP-027` | `SRV-REQ-062` to `SRV-REQ-065` | Owner modules, public APIs, and split-facet example | Server code does not own Ref fields, candidate meaning, record meaning, placement, or cluster authority. Cross-package release proof remains with seam 99. | `Resolved for Server`; delivery follow-up |
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
| A persistent child specification keeps only Ref and instance as restart source. | `Defer`. | Ref and namespace now exist, but current child restart contracts still require their compatible options. Seam 10 owns any topology-level source change. |
| Runtime handles never enter Agent or checkpoint data. | `Retain`. | Current state, checkpoint, and child tests support this invariant. |
| The runtime has exactly four phases and no `admitting` phase. | `Replace`. | Current public status exposes five total phases. Keep them for compatibility. |
| Plugin preparation must be hidden inside `running`. | `Remove as a phase rule`. | `admitting` is current public data. Seam 04 owns evaluator stages, not Server phases. |
| Persistent creation starts provisional runtimes, waits, writes revision zero, and then publishes. | `Implemented`. | The Registry reserves identity as `:starting`; public lookup and listing accept only `:ready`. |
| Recovery workers can resume pending work while later Turns continue. | `Retain as capability behavior`. | Explicit capability state can do this. Ordinary Directives receive no replay guarantee. |
| One public control model must expose only `evaluate`, `commit`, and `directive`. | `Replace`. | Current Outcomes use five supported stages. Keep them until seam 13 approves migration. |
| `turn_timeout` covers route, preparation, execution, contribution, and validation. | `Implemented with live admission`. | One 5-second default limit starts with active work and is cancelled when commit begins. `:infinity` disables it. |
| Mailbox wait is outside the Turn limit. | `Retain`. | Caller admission deadline covers postponed time. The Server limit starts with active work. |
| Cancellation terminates owned work, rejects late results, and preserves state. | `Implemented`. | Deterministic cancel-first and completion-first tests preserve current result values. |
| Persistence timeout is an indeterminate write and stops authority. | `Retain conditionally`. | Seam 07 deferred the option. If configured by owning seams, the result meaning is indeterminate. |
| Directive timeout is post-commit failure and creates no replay duty. | `Retain`. | Current commit retention works. Effect completion can remain uncertain. |
| Cancellation and completion races are decided by the first processed event. | `Implemented`. | `:gen_statem` serialization and both race-order tests prove the rule. |
| The facade must expose a fixed list of Ref-first command and lifecycle functions. | `Implemented by seam 09`. | The instance owns names, namespace checks, resolution, and public lifecycle policy. |
| `start_agent` and `activate_agent` must define complete startup semantics here. | `Split ownership`. | This seam owns Server readiness. Seam 09 owns facade and publication. Seam 07 owns record meaning. |
| Public runtime options include partition, Turn, readiness, Directive, dispatch, error, idle, and postponed limits. | `Implemented for Server-owned limits`. | `turn_timeout` is separate from caller, readiness, persistence, Directive, and idle limits. Instance-owned fields stay outside this seam. |
| Error policy must become only closed `continue` or `stop` data. | `Replace with staged compatibility`. | Current Signal, maximum-count, and function policies are supported. They cannot override safety invariants. |
| Controlled policy stop must not restart a transient child. | `Retain`. | Current shutdown normalization and tests prove this behavior. |
| `call` success proves commit but not Directive completion. | `Retain`. | This matches current code and seam 06. |
| `cast :ok` confirms only message send and can later be dropped. | `Retain`. | This is current documented behavior. |
| OTP asynchronous request envelopes must stay standard. | `Retain`. | Seam 12 registers this protocol. |
| Caller timeout after start does not cancel the Turn. | `Retain`. | Current test evidence proves it. |
| Stable cancellation results must be `turn_cancelled`, `no_active_turn`, `turn_mismatch`, and `too_late`. | `Retain target; migrate`. | Current atoms differ. Seam 12 owns error shape and codes. |
| Same-Agent synchronous reentry must fail. | `Retain`. | Current code covers admission, executable, and Directive process trees. |
| Every persistence write error must stop with lost write authority. | `Implemented by seam 06`. | Preserve caller failure, activation stop, and restore-first recovery during seam-08 work. |
| Framework invariant failure must crash and use the configured restart source. | `Retain`. | Fault classification and recovery proof must be complete. |
| Plugin replacement must receive matching state and state version. | `Implemented`. | The owner builds a new Init and child specification for each runtime generation. |
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
| `SRV-REQ-005`, `SRV-REQ-006` | Options, public construction, and definition-version tests | Keep through later authoring changes | `Proven` |
| `SRV-REQ-007` | PID/name lookup plus seam-09 Ref-to-handle resolution | None | `Proven across owner seams` |
| `SRV-REQ-008` | Seam-07 lifecycle plus seam-09 stable Ref record and rebind tests | None | `Proven across owner seams` |
| `SRV-REQ-009` to `SRV-REQ-011` | Revision-zero create, cleanup, and strict publication tests | None in this seam | `Proven` |
| `SRV-REQ-012` to `SRV-REQ-017` | Public API, async request, caller-timeout, compatibility, and additive Ref-facade tests | None | `Proven across owner seams` |
| `SRV-REQ-018` to `SRV-REQ-022` | Postponement, overload, and bounded cast observation | None | `Proven` |
| `SRV-REQ-023` | Reentry tests for all three owned process trees | None | `Proven` |
| `SRV-REQ-024` to `SRV-REQ-027` | Source-first selection, ordered admission, and exact Exec target tests | None | `Proven` |
| `SRV-REQ-028`, `SRV-REQ-029` | Whole-Turn timer, task stop, stale result, state, and Outcome tests | None | `Proven` |
| `SRV-REQ-030`, `SRV-REQ-031` | Cancel-first, completion-first, and directing rejection tests | None | `Proven` |
| `SRV-REQ-032` to `SRV-REQ-038` | Candidate, Directive, persistence, equal-state, reply, and order tests | One requirement-mapped commit-order matrix | `Proven` |
| `SRV-REQ-039` | Confirmed-conflict, known-error, and indeterminate-write stop cases | Every CAS failure stops before new evaluation | `Proven by seam 06` |
| `SRV-REQ-040` | Runtime lifecycle restart test | Keep after identity and checkpoint migration | `Proven` |
| `SRV-REQ-041` | Split Agent/Server facet runtime and readiness tests | None | `Proven` |
| `SRV-REQ-042` | FA-06 immutable bootstrap pair tests | None | `Proven` |
| `SRV-REQ-043` to `SRV-REQ-045` | Restart visibility, no-fallback, and readiness failure tests | None | `Proven` |
| `SRV-REQ-046` | Split-facet and recoverable-capability Signal tests | Cross-package proof belongs to seam 99 | `Proven in Core` |
| `SRV-REQ-047` to `SRV-REQ-049` | Directive order, failure, timeout, and commit tests | Keep through facet and error migration | `Proven` |
| `SRV-REQ-050` to `SRV-REQ-052` | Child lifecycle and distributed child tests | Keep exact uncertainty without adding topology authority | `Proven` |
| `SRV-REQ-053` | Crash at first and second Directive positions | None | `Proven` |
| `SRV-REQ-054`, `SRV-REQ-055` | Hibernate, active-record, and tombstone lifecycle tests | Provider retention stays provider-owned | `Proven` |
| `SRV-REQ-056`, `SRV-REQ-057` | Termination, timeout, cancellation, and runtime-boundary tests | None | `Proven` |
| `SRV-REQ-058` | Outcome schema and runtime tests | Keep after final error and observation projection | `Proven` |
| `SRV-REQ-059` | Crash-and-restore debug observation test | None | `Proven` |
| `SRV-REQ-060` | Definition match, mismatch, missing legacy revision, and no-readiness tests | None | `Proven` |
| `SRV-REQ-061` | Exact Exec target and loaded-code non-pinning documentation | None | `Proven` |
| `SRV-REQ-062` to `SRV-REQ-064` | Owner boundary and dependency checks | Preserve through dependent seams | `Proven` |
| `SRV-REQ-065` | Split-facet example uses only public Plugin and Agent Server contracts | External package build belongs to seam 99 | `Proven in Core` |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| PID and name API | Keep all documented current operations beside the implemented Ref-first instance calls. |
| Startup | Keep module, neutral definition, and Agent instance inputs. Add revision and initial-write checks without changing canonical construction ownership. |
| Identity | Keep IDs and term-valued partitions. Ref-first operations require the implemented namespace and binary-or-`nil` Ref partition. |
| Status | Keep the current map and five phase atoms. Add fields only through an owner-documented compatible form. |
| Snapshot and Outcome | Keep the snapshot map and current validated Outcome. Seam 13 must inventory consumers before changing fields, Signals, or stages. |
| Debug | Keep bounded `set_debug` and `recent_events`. A later removal needs observation replacement proof and security review. |
| Error controls | Convert one public boundary at a time through seam 12. Keep OTP request envelopes and best-effort cast `:ok`. |
| Error policy | Keep current policy forms until a separate deprecation. Make persistence authority, commit retention, and batch stop non-overridable first. |
| Routing and Plugins | Change fixed source selection and facet callbacks as one compatible unit. Do not strand a Plugin that changes routes under the old contract. |
| Turn limit | Keep `turn_timeout` separate from caller wait, Directive timeout, and lower `Jido.Exec` option meanings. |
| Persistence | Roll out initial create, CAS classification, authority stop, public errors, and activation recovery together. Keep legacy records readable. |
| Runtime checkpoints | Keep same-instance abnormal-restart recovery. Clean instance stop continues to remove nondurable checkpoints. |
| Plugin runtime Init | Keep state and version in each new Init while current state-pull APIs remain. Do not reuse a prior generation's Init. |
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
| `SRV-BLK-001` | `Resolved` | 00 Overview | The Overview direction and Server owner boundary are selected. | No action. |
| `SRV-BLK-002` | `Resolved` | 90 Package boundaries | Agent Server remains in Core and public API compatibility is retained. | Keep cross-package proof in seam 99. |
| `SRV-BLK-003` | `Resolved` | 12 Errors and contracts and 08 Agent Server | Current controls stay compatible. `agent_turn_timeout` is one registered owner code. | Preserve the stable-code registry. |
| `SRV-BLK-004` | `Resolved` | 01 Agent and 02 Agent authoring | Agent version, default checkpoint behavior, and canonical authoring are implemented and approved at `fa17a6d6` and `ae559f4f`. | No action. |
| `SRV-BLK-005` | `Resolved` | 09 Jido instance | Namespace binding, stable persistence identity, and the Ref-first facade are implemented without removing current handles. | Preserve the local-only boundary. |
| `SRV-BLK-006` | `Resolved` | 04 Turn evaluation and 05 Plugins | Source-Signal selection and owner-specific facets are implemented. | Preserve their order. |
| `SRV-BLK-007` | `Resolved design input` | 06 Commit, 07 Persistence, 08 Agent Server | Every required write error now stops the activation, returns the failure, and requires restore-first reactivation. | Preserve the rule during seam-08 lifecycle work. |
| `SRV-BLK-008` | `Resolved` | 07 Persistence and 08 Agent Server | Revision-zero create and strict ready publication are implemented. | Preserve their order. |
| `SRV-BLK-009` | `Resolved` | 05 Plugins and 08 Agent Server | Runtime Init contains only the paired owned state and matching state version. | Keep the state-pull compatibility path. |
| `SRV-BLK-010` | `Resolved` | 08 Agent Server | `turn_timeout` starts with active work and ends when commit begins. | Keep other operation limits separate. |
| `SRV-BLK-011` | `Resolved compatibility rule` | 08 Agent Server and 13 Observability | Current status, Outcome, and debug contracts remain. | Seam 13 can add a bounded projection without changing these values. |
| `SRV-BLK-012` | `Out of scope` | 10 Runtime topology | Explicit known-node child operations grant no cluster authority. | Keep placement and authority outside this seam. |
| `SRV-BLK-013` | `Resolved design` | 04 Turn evaluation and `jido_action` | Agent `vsn` does not pin loaded Action or Flow code. | V3 uses the code loaded when `Jido.Exec` invokes the selected executable. |
| `SRV-BLK-014` | `Deferred` | Separate future seam | No public need or safe contract exists for `code_change/4`. | Do not claim hot private-state migration in V3. |
| `SRV-BLK-015` | `Resolved` | Design index and dependent seam owners | The main review table and dependent seams now use the Agent Server briefing, design, and alignment files. | Keep repository-wide link checks in the documentation gate. |

## Completion criteria

- [x] The selected implementation records every `SRV-DEC` item.
- [x] Prerequisite implementation inputs are present.
- [x] Every Server-owned `SRV-REQ` item has `Proven` evidence.
- [x] No unresolved `Conflict`, `Missing`, or `Blocked` entry remains for an
      approved requirement.
- [x] Source-Signal selection, whole-Turn timeout, cancellation race, and late
      result behavior have deterministic tests.
- [x] Initial durable create and every persistence result have one publication,
      state, Directive, authority, caller, and restart result.
- [x] Every Plugin runtime generation receives matching committed state and
      version.
- [x] Ordinary Directive interruption has non-replay and no-reconstructed-
      settlement proof.
- [x] Current API, status, Outcome, debug, error-policy, and child behavior
      remain supported until their separate migration gates pass.
- [x] No Agent Server requirement defines Ref fields, namespace binding,
      instance namespace policy, placement, transport, or cluster authority.
- [x] Public module docs, types, dependent seams, and the main design index use
      the approved contract.
