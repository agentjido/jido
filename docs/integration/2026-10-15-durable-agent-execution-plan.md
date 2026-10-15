# Durable Agent execution implementation plan

Status: Pending approval. Date: 2026-10-15. Design and implementation plan only.

The contract is in the
[durable execution design](../design/08_agent-server/durable-execution.md).
This plan names implementation steps and evidence. It does not approve its own
design. Keep all work in the `jido` repository. Do not change or commit Action
or Runic as part of this plan.

## Intended result

An Agent commits business state and responsibility for a workflow in one CAS.
Runic executes the workflow with its real Store. After a crash, Core reads that
responsibility and recovers the same workflow. A later completion Turn applies
the result to current Agent state. Its commit also acknowledges the result.

Ordinary Agent APIs keep their existing result meanings. No generic durable
inbox, distributed ownership, or durable replay of ordinary Directives is added.
Required Plugin hooks keep their order and failure boundary.

## Starting state and change control

The local Core branch is `release/v3`, with checkpoint commit `4e9112df` and
uncommitted integration changes. Preserve those changes and the separate
`docs/design/GAP_ANALYSIS.md` edit. Do not reset the working tree. Review the
current diff before each implementation slice.

Fixed dependency baselines:

| Repository | Revision | Existing local changes |
| --- | --- | --- |
| Action, `release/v3` | `58db4d05bafcb080a4735673214e8508b08178e0` | Local Runic path in `mix.exs`; corresponding `mix.lock` change |
| Runic, `main` | `fc4b8b0b72f1262b144664938aee240b3810e650` | None |

Core is not a green baseline after the dependency reset. Prior checks found
unsupported `mode` and `owner` options and non-portable fixture data. The old
full-suite pass does not apply to these restored dependencies. Capture new
test evidence before implementation. Do not report existing failures as new
regressions or hide them with dependency changes.

## Phase 0 — Review contracts and prove public API use

1. Review the proposed package exception in seam 90, errors in seam 12,
   portability in seams 01 and 04, hook order in seam 05, atomic intent in seam
   06, record ownership in seam 07, and runtime control in seam 08. Then review
   the instance and observation effects in seams 09 and 13.
2. Capture `git status --short --branch` in each repository. Save a Core diff
   inventory so later verification can identify this work's changes.
3. Capture the failing Core started-execution and ordinary portable call
   tests with the fixed dependency versions.
4. After implementation is authorized, add focused Core contract tests for
   public `Exec.start`, `resume`, `result`, Runic manual dispatch, checkpoint,
   stop, cancellation, and full event-log round trips. Use both an Action and
   a multi-node Flow. Include a Flow condition and nested Flow.
5. Prove the four design gates: initial-input classification, Store codec,
   manual native restart, and attached owner-death cleanup. Use public APIs;
   do not read private Worker state or copy Action identity code.

Exit evidence: `DUR-T04`, `DUR-T05`, and `DUR-T13` prove the required public
behavior. A failed proof stops the affected slice and produces a revised
design or a named limitation. It does not authorize an Action or Runic patch.

## Phase 1 — Restore the supported started execution boundary

Primary files: `lib/jido/agent_server/execution.ex`, `active_turn.ex`,
`cancellation.ex`, `turn.ex`, `lib/jido/agent/runner.ex`, and their tests.

1. Remove unsupported managed options. Keep one started execution per attached
   Turn and use only the current Action option set.
2. Add the minimal Core execution guard for attached work. Supervise it outside
   the AgentServer it watches. Track the known workflow id through pending
   start, owner death, completion, and confirmed cleanup. Keep it separate from
   delegated execution recovery.
3. Migrate non-portable fixture and Plugin runtime data to stable service ids
   resolved at use. Reject unsupported live values explicitly. Keep candidate
   and Directive validation before Agent commit.
4. Retain pre-commit cancellation, Turn deadlines, caller wait semantics,
   post-commit hook order, and stale-result rejection.
5. Correct the earlier integration documentation and tests that assert
   execution-level `persist: false`, a local managed mode, or a managed owner
   option. Do not silently weaken cleanup tests.

Exit evidence: focused AgentServer execution, context, cancellation, Plugin,
and failure-contract tests pass against the unchanged dependencies. The guard
has no retry policy, domain state, or duplicate scheduler.

## Phase 2 — Add durable records and migration

Primary files: `lib/jido/persistence/record.ex`, `persistence.ex`,
`agent_server/storage.ex`, `agent_server/state.ex`; new record and value modules
under `lib/jido/execution/` and `lib/jido/command/`.

1. Define static Zoi schemas for execution Ref, command receipt, execution
   intent, terminal outcome, and the runtime envelope. Add structured error
   codes for conflicts, closed epochs, size limits, capacity, and attention.
2. Introduce format 4. Keep record revision as CAS revision; add state version.
   Read format 3 and migrate with CAS before admitting new durable work.
3. Preserve the runtime envelope independently of Agent checkpoint callbacks.
   Add identity validation and incarnation preservation across restore.
4. Update create, save, load, tombstone, hibernate, thaw, definition replacement,
   and direct persistence APIs. Reject writes that could erase pending work.
   Define both versions in public inspection and persistence return values.
5. Add bounded receipt storage, command epochs, bounded execution history,
   sequence retirement, and byte-size limits. Do not add automatic expiry.

Exit evidence: `DUR-T01`, `DUR-T03`, `DUR-T11`, and `DUR-T12` cover migration,
concurrency conflicts, exact shapes, custom checkpoints, and stale identities.
No runtime work starts in this phase.

## Phase 3 — Connect the real Runic Store

Primary files: new `lib/jido/persistence/runic_store.ex`, instance options and
supervision in `lib/jido.ex` and `lib/jido/application.ex`.

1. Implement only Runic's required full-snapshot Store callbacks over Core's
   existing byte Store. Use a distinct key prefix and versioned log codec.
2. Add CAS acknowledgement handling. After an uncertain write, read and compare
   complete bytes before confirming an identical retry. Block conflicting or
   unresolved writes. Do not use an in-memory success cache as durable proof.
3. Add opt-in instance configuration, deployment identity, and versioned
   profiles. Resolve callbacks and resource handles from instance config. Add
   a separate DurableExecRunner; keep attached Turns on the existing Runner.
4. Reject mismatched per-Agent persistence in version one. Keep the default
   non-durable instance path available. Label ETS recovery correctly.
5. Test a full instance restart with a persistent test adapter. Verify that
   the Runic Store survives independently of the Worker and its ETS registry.
6. Add acknowledged-snapshot retirement for explicit execution pruning. Keep
   physical deletion with the backend; never retire data before Agent ack.

Exit evidence: `DUR-T04`, `DUR-T05`, `DUR-T06`, and `DUR-T09` pass without Store
or Exec modifications in a dependency. Snapshot size and encoding errors are
visible and do not acknowledge a write.

## Phase 4 — Commit command receipts and execution intent

Primary files: `lib/jido/agent/directive.ex`, new Directive structs,
`agent_server/turn.ex`, `post_commit.ex`, `storage.ex`, `admission.ex`,
instance facade APIs, and a private `agent_server/durability.ex` handler.

1. Add `Jido.command`, receipt lookup, and status types. Deduplicate a committed
   command before Plugin admission and executable evaluation. Check id,
   incarnation, epoch, fingerprint, and receipt capacity.
2. Add typed StartExecution and CancelExecution constructors. Validate a
   single-item durable Directive batch before commit. Reject a second
   unacknowledged execution and a full terminal history. Add the reserved
   portable execution summary to Turn context for business cancellation.
3. Allocate the execution sequence once. Build state, receipt, and intent in
   one Agent record CAS. Reply with the receipt after confirmed commit.
4. Preserve required after-commit callbacks. Release intent only after they
   succeed. On restart, auto-release only when no required hook existed.
   Block uncertain hook execution without replay or a bypass API.
5. Keep direct administrative cancellation separate from business cancellation
   through a Signal. Add epoch close and acknowledged-prefix pruning.

Exit evidence: `DUR-T02`, `DUR-T03`, `DUR-T10`, and `DUR-T12` prove atomic
responsibility, receipt semantics, hook gates, and bounded retention. No test
claims that a call receipt confirms business completion.

## Phase 5 — Add AgentServer recovery transitions

Primary files: `agent_server.ex`, `state.ex`, `server_lifecycle.ex`,
`durability.ex`, `execution.ex`, `task_support.ex`, and inspection modules.

1. Add restoring and recovering startup work before ordinary admission.
   Classify the stored operation, versioned configuration, release gate,
   cancellation, and attention state.
2. Start or resume in manual mode. Confirm input persistence, CAS running
   control state, then enable Runic dispatch. Handle the build-only window
   through the proven public snapshot classification.
3. Handle Worker replacement from confirmed Store data. Do not adopt a new PID
   as proof that recovery occurred. Register a transient PID dispatch permit
   in the instance RuntimeStore before continue. Adopt a surviving Worker only
   when its permit matches. Use generation-tagged supervised tasks.
4. Add named reconciliation timers and restore absolute deadlines. Keep one
   external control operation per internal callback. Preserve ordinary OTP
   Signal postponement and one active Turn.
5. Serialize record writes with business commits. If control work and a Turn
   overlap, use the latest envelope and checkpoint; never apply task-captured
   Agent state. Use one CAS write slot and an explicit state change to release
   postponed write requests. Stop the activation after any failed
   Agent-record write.
6. Keep delegated work alive across AgentServer death. Reject hibernate,
   definition replacement, and delete while acknowledgement is pending.

Exit evidence: `DUR-T04`, `DUR-T05`, `DUR-T08`, and `DUR-T09` prove recovery and
authority loss. Status and cancel calls remain responsive during Runic I/O.
Core contains no runnable scheduling or workflow graph mutation loop.

## Phase 6 — Store terminal outcomes and acknowledge completion

1. Treat completion callbacks as hints and add reconciliation for lost hints.
   Check Action result and Runic admission state outside callback execution.
2. Confirm the terminal checkpoint and persisted Worker stop before saving the
   terminal outcome in the Agent envelope. Retain workflow data until the
   completion acknowledgement commits.
3. Deliver a stable completion Signal through normal Agent admission. Use a
   private delivery capability so public Signal fields cannot forge an ack.
4. Evaluate against current Agent state. Commit the candidate and completion
   acknowledgement in one CAS. Suppress duplicate delivery before evaluation.
5. On reducer failure, retain the outcome and require explicit reconciliation.
   On uncertain workflow work, stop automatic recovery and expose the cause.
   Normalize error values for storage. Reject nonempty deferred workflow
   effects explicitly; do not replay or discard them.
6. Apply cancellation races through the stored control CAS. Confirm native
   work stop before delivering a cancelled outcome. Document external effect
   uncertainty; do not claim rollback.

Exit evidence: `DUR-T06`, `DUR-T07`, and `DUR-T08` prove terminal delivery,
duplicate suppression, concurrent business changes, and cancellation order.

## Required acceptance groups

| Group | Required evidence |
| --- | --- |
| DUR-T01 | Independent record and state versions; format 3 migration; exact format 4 shapes; incarnation and tombstone preservation; no metadata loss through legacy save paths |
| DUR-T02 | Crash before intent CAS starts no work; crash after it retains intent; candidate, command receipt, and intent are never partially committed |
| DUR-T03 | Identical duplicate skips admission and execution; conflicting data reject; timeout followed by receipt lookup; capacity and closed epoch behavior after restart |
| DUR-T04 | Action and Flow start in manual mode; crash before and after input checkpoint; build-only Store; single root classification; no private Action identity access |
| DUR-T05 | Worker crash and native replacement; AgentServer kill with a live Worker; RuntimeStore worker restart; Runner restart; full instance restart; PID permit checks; same workflow id; configuration mismatch; no dispatch before restore gate |
| DUR-T06 | Callback with failed persistence; lost callback; terminal checkpoint failure; crash after Worker stop but before terminal Agent CAS; terminal result survives restart; deferred effects block delivery |
| DUR-T07 | Ordinary Turn commits while workflow runs; completion uses new state; crash before and after completion CAS; duplicates and forged acks; reducer failure retains outcome |
| DUR-T08 | Cancel before start, during staging, and during work; success/cancel race in both orders; caller timeout leaves work; deadline restore; cancelled checkpoint never resumes |
| DUR-T09 | Confirmed CAS conflict, rejected write, and lost acknowledgement; identical snapshot reconciliation; control/business write serialization; postponed writes resume; no further Agent Turn after write authority is lost |
| DUR-T10 | Existing Plugin declaration order; hook failure after commit; crash in hook window; no automatic hook replay; no StartExecution mixed with ordinary Directives |
| DUR-T11 | PIDs, functions, ports, refs, credential resource-id resolution, oversized records and outcomes; profile/deployment mismatch; complete workflow log codec round trips |
| DUR-T12 | One unacknowledged operation; full history; explicit pruning; stale completion after pruning or recreation; delete/hibernate/upgrade rejection while work is pending |
| DUR-T13 | Attached owner death before start, during start, during work, and during cleanup; cancelled native scopes; late results cannot commit; unchanged caller and Turn timeout meanings |

Use barriers and monitors in failure tests. Do not use elapsed sleeps as proof
that a write or stop occurred. Inject failure at each named write, dispatch,
and acknowledgement boundary. Test exact transitions and stored records.

## Final verification and human review

Run focused groups after their slice, then these checks from `jido/`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test.all
mix test.persistence
mix quality
```

The persistence conformance alias uses its configured test adapters. Run any
required service-backed adapter checks with the documented services and
credentials. Record unavailable services as unverified; do not call them
passed. Check that snapshot storage works with every adapter advertised for
the durable capability.

Add one example with a short decision Turn, a multi-step delegated Flow, an
unrelated Agent update during the Flow, an AgentServer restart, and completion
against current state. Add a hook-window example that shows visible blocked
responsibility. Update public docs and design alignment evidence after tests.

Before human review:

- Compare Action and Runic HEAD, status, and diffs with the fixed baselines.
- Confirm that all new source and tests are in Core.
- Confirm that Core has no duplicate Runic scheduler, checkpoint engine,
  generic Directive replay log, or cluster ownership claim.
- Report remaining recovery limits, API changes, and baseline failures.
- Leave changes uncommitted for human review unless the user later asks for a
  commit.

## Simplification test

Success does not mean fewer total lines. It means one owner per decision:
AgentServer commits Agent state; Runic advances workflows; the Store confirms
persistence. Core stores the handoff and acknowledgement between them.

Remove the prior dependency bypass assumptions, pre-commit durable cleanup,
and any duplicate workflow scheduling. Keep each added runtime task tied to a
named transition and failure test. If a new Core component owns graph progress
or retries individual nodes, the implementation has crossed the design boundary.
