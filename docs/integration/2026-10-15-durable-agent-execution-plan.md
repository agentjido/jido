# Compiled Agent behavior and durable execution implementation plan

Status: Superseded for the current release on 2026-10-29. Documentation only.

The current release keeps new-only persistence record format 1 and Agent
snapshot format 1. It does not implement the record migration proposed below.

The contract is in the
[durable execution design](../design/08_agent-server/durable-execution.md).
It includes the proposed Agent DSL, durable records, report protocol,
`gen_statem` transitions, requirements, and Flow gap register. This plan defines
the implementation order and required evidence. It does not approve or start
implementation.

Action and Runic remain unchanged. No dependency patch, dependency reset,
commit, or source implementation is part of this documentation task.

## Intended result

An Agent definition describes state, inputs, capabilities, behavior, and commit
points. The AI extension lowers its concepts to the canonical Core definition.
A trusted compiler constructs concrete Flow graphs from accepted plans.
Runic owns execution inside each graph. AgentServer owns serialized Agent
commits and the durable obligations that link graphs to that Agent.

One logical execution can cross several semantic commit points. Each bounded
Flow segment can contain many model calls, tool calls, choices, iterations,
and native parallel branches. A segment report requests an Agent commit.
That commit records its receipt and next action together. The next action is
a segment intent, a semantic wait, or final acknowledgement.

The first path uses the current public Flow result boundary. It does not claim
live graph suspension, arbitrary Runic component support, hot graph mutation,
or direct multi-input resume through `Jido.Exec`.

Ordinary Agent APIs keep their current result meanings. Required Plugin hooks
keep their order. There is no generic durable inbox, distributed ownership,
universal Directive outbox, or second graph scheduler in Core.

## Starting state and change control

These revisions were read during this documentation task:

| Repository | Branch and revision | Working state at inspection |
| --- | --- | --- |
| Core | `release/v3`, `a5a0ae9c1e8fa874fa7368b1136bb63513aaa5ae` | Untracked `test/jido/topology/authoring_consistency_test.exs`; preserve it |
| Action | `release/v3`, `87eaaefcaddc61bf08e7542cfbf93a2f73411cf4` | Clean |
| Runic | `main`, `fc4b8b0b72f1262b144664938aee240b3810e650` | Clean |

These replace the older dependency-reset baseline in the prior plan. No tests
were run for this documentation revision. The earlier green suite and earlier
dependency-reset failures do not establish the current test result. Capture a
fresh baseline when implementation is authorized.

Before each implementation slice, read repository instructions, check branch
and status, and inventory existing changes. Keep each package's source, tests,
checks, and eventual commit in that package. Preserve unrelated work. Do not
infer authority to edit Action or Runic from a failed proof gate.

## Ownership and prerequisite decisions

| Owner | Planned responsibility |
| --- | --- |
| Core | Agent record, execution identity, report and input receipts, control Directives, serialized commits, Runic Store bridge, runtime reconciliation |
| `jido_ai` | Proposed AI DSL, canonical lowering, trusted catalog, plan validation, Flow construction, AI state, model and tool adapters, replay policy |
| Action | Existing executable and Flow contracts; no changes in this plan |
| Runic | Existing graph runtime, scheduling, checkpoints, and Store protocol; no changes in this plan |
| Application | Business reducers, domain preconditions, capability configuration, and durable backend choice |

The later AI phases are a separate package workstream. They use the public Core
contracts established first. They do not add AI clauses to AgentServer or use
its private state. A Core-only implementation can prove the protocol with
neutral fixtures before the AI extension exists.

Review contracts in this order:

1. Package boundary and structured errors: seams 90 and 12. The narrow Core
   recovery exception remains pending; the approved package boundary is not
   silently rewritten by this plan.
2. Agent, authoring, and identity: seams 01, 02, and 03. Retain complete Agent
   domain state and canonical lowering across authoring forms.
3. Turn, Plugin, and commit: seams 04, 05, and 06. Retain one selected
   executable, Plugin field ownership, validation, and required hook order.
4. Persistence and AgentServer: seams 07 and 08. Keep the current exact
   format-1 boundaries. Review any future runtime envelope as a separate break.
5. Instance and observation: seams 09 and 13. Distinguish progress, stored
   reports, commit receipts, and completed executions.

No new plan entry is an approved prerequisite alignment. Update the owning
seam documents after review. Do not mark them approved without explicit user
approval.

## Phase 0 - Prove the fixed public APIs

Package: Core consumer tests. No production implementation before the design
and this plan are approved for that work.

1. Capture the current Core test baseline and dependency revisions. Recheck
   current execution options, portability, cleanup, and result semantics.
2. After implementation is authorized, write focused contract probes using
   only public APIs. Cover Action modules, module Flows, and runtime Flow
   documents built with a trusted Registry.
3. Exercise compile, Codec encode/decode, manual start, input checkpoint,
   result, persisted stop, resume, cancellation, and full log round trips.
   Include nested Flow, choice, map/reduce, iterate, and dispatch where used.
4. Prove public initial-input classification. Distinguish a build-only log
   from admitted input without reading Worker state or copying Action's
   private managed identity.
5. Prove manual native Worker replacement cannot dispatch before recovery.
   Prove attached owner-death cleanup during pending start.
6. Compile a research-shaped graph with a native parallel collection and
   fan-in. Inspect actual graph structure and outputs. Do not accept a single
   Action that runs a second graph interpreter.
7. Record an outcome for every `FLOW-GAP-001` through `FLOW-GAP-011`: supported
   and proven, unsupported, or blocked on a named public API contract.

Exit evidence: `DUR-T04`, `DUR-T05`, `DUR-T13`, `DUR-T15`, and `DUR-T20`.
Block only the affected capability when a proof fails. Report the precise
limit. A failed probe does not permit an Action or Runic patch.

## Phase 1 - Align attached execution with current dependencies

Package: Core. Primary boundary: `lib/jido/agent_server/execution.ex`, Turn,
cancellation, and execution guard modules.

1. Change only mismatches established by Phase 0. Use the current supported
   managed option set. Do not assume an old dependency-reset failure remains.
2. Keep one started execution per attached Turn. Keep candidate and complete
   Directive validation before Agent commit.
3. Use a minimal supervised guard if attached owner cleanup still needs it.
   Track the known workflow ID through start, owner death, and confirmed stop.
   Give the guard no domain state, graph progress, or retry policy.
4. Replace live handles in managed input with stable service IDs where needed.
   Preserve structured errors for unsupported values; do not remove fields
   silently or serialize a PID to conceal the problem.
5. Retain caller wait semantics, Turn deadlines, pre-commit cancellation,
   required post-commit hooks, and stale-result rejection.
6. Correct earlier integration documentation that claims unsupported owner,
   local-mode, or execution-level persistence options.

Exit evidence: focused existing execution, context, Plugin, cancellation, and
failure-contract tests pass. `DUR-T13` proves cleanup. Existing behavior changes
are listed separately from the new durable protocol.

## Phase 2 - Define durable values without a record migration

Package: Core. Primary files: persistence record and storage modules; new
typed values under execution and command namespaces.

1. Define static Zoi schemas for execution Ref, target descriptor, behavior
   binding, segment intent, report, commit receipt, input receipt, semantic
   wait, terminal outcome, artifact envelope, and runtime envelope.
2. Do not add an in-place record migration. The current release reads and
   writes exact persistence record format 1 and Agent snapshot format 1.
   Reject unknown formats. A future runtime envelope needs a separate reviewed
   breaking shape.
3. Store encoded Flow documents and plan artifacts by exact document digest
   inside the runtime envelope. Record registry, catalog, compiler, behavior,
   and deployment versions. Reject unavailable versions before dispatch.
4. Keep runtime control outside the Agent domain checkpoint. Preserve it
   across custom checkpoint callbacks, save, restore, tombstone, and hibernate
   paths. A plain Agent save cannot erase accepted work.
5. Add stable execution and segment sequences, report IDs allocated before
   dispatch, per-key admission, finite active capacity, and retention bounds.
6. Retain report and input receipts until explicit execution pruning. Preserve
   the retired execution boundary and logical incarnation after pruning.
7. Enforce both per-value and complete-record size limits. Keep large external
   artifact references unsupported until their own immutable storage contract
   is defined.

Exit evidence: `DUR-T01`, `DUR-T03`, `DUR-T11`, and `DUR-T12`. This phase starts
no workflow and adds no graph traversal.

## Phase 3 - Connect the real Runic Store

Package: Core. Primary files: a Runic Store bridge, instance options, and
instance supervision.

1. Implement the required full-snapshot Store callbacks over the Core byte
   Store. Use a separate key prefix and versioned Runic event codec.
2. Prove save/load for all three target descriptor kinds. Validate portable
   payloads separately from Runic executable descriptions. Never strip event
   fields or acknowledge an unsupported log.
3. Confirm identical bytes by read after an uncertain snapshot write. Block a
   conflicting value or unresolved write. CAS is not a distributed fence.
4. Add opt-in durability configuration, versioned profiles, finite execution
   capacity, and a separate durable Runner. Keep attached Turn snapshots out
   of the durable segment key space.
5. Rebind portable service IDs, context, and policy on resume. Keep credentials
   and live clients in trusted runtime configuration. Reject unsupported
   per-Agent Store differences in the first path.
6. Verify full instance restart with a persistent test adapter. Label ETS
   recovery as VM-local. Retain every needed segment snapshot until execution
   pruning; use acknowledged retirement records before physical cleanup.

Exit evidence: `DUR-T04`, `DUR-T05`, `DUR-T06`, `DUR-T09`, and `DUR-T11`.
No in-memory observation or callback substitutes for a Store acknowledgement.

## Phase 4 - Accept work and recover segments

Package: Core. Primary boundary: typed execution Directives, Turn validation,
storage, AgentServer lifecycle, and a private control handler.

1. Add command receipts and lookup. Deduplicate before admission and
   evaluation. Keep the existing distinction between a committed decision and
   successful delegated work.
2. Add StartExecution and CancelExecution. Permit one execution control
   Directive in a batch. Validate behavior key, profile, target, declared report
   bindings, replay policy, and capacity before commit.
3. CAS the Agent candidate, command receipt, execution identity, first segment
   intent, and stored artifacts together. A constructor starts no process.
4. Preserve required after-commit hook order. Release each segment only after
   the related hook gate. Retain attention for an uncertain required hook;
   do not replay it or add a bypass that asserts success.
5. Recover known execution Refs before readiness. Start or resume segments in
   manual dispatch mode. Confirm input checkpoint and store running control
   before continue. Apply the same gate after native Worker replacement.
6. Key transient dispatch permits by execution Ref, segment sequence, and PID.
   Adopt a live Worker only after a matching permit and public status check.
   A replacement PID is not proof of recovery.
7. Serialize all Agent-record writes in one write slot. Use the latest runtime
   envelope at CAS construction. Task results are operation results, not old
   replacement Agent snapshots. Stop after an unconfirmed Agent write.
8. Use generation-tagged tasks, named reconciliation timers, bounded work per
   callback, and rotating selection across active executions. Keep one active
   Turn and one external workflow control task per Agent.

Exit evidence: `DUR-T02`, `DUR-T03`, `DUR-T04`, `DUR-T05`, `DUR-T08`,
`DUR-T09`, `DUR-T10`, and `DUR-T12`. Core does not select graph nodes or retry
individual runnables. Status and cancellation remain responsive during I/O.

## Phase 5 - Implement the execution/commit protocol

Package: Core. Primary boundary: report validation, internal delivery,
candidate commit, receipt lookup, and next-segment release.

1. Treat completion notifications as hints. Read the public result, confirm
   its checkpoint, and stop the completed segment with persistence before
   storing a pending report. Cover lost notifications by reconciliation.
2. Validate report identity, fingerprint, binding, schema, basis, plan revision,
   continuation, size, and empty deferred-effect list. A binding chooses an
   ordinary Signal route. Public Signal fields cannot grant internal delivery
   authority.
   Validate proposed artifacts and generic program adoption before commit;
   Core does not interpret AI plans. Intermediate report Turns use an empty
   Directive batch; final reports retain ordinary Directive semantics.
3. Deliver a stored report through normal admission and Turn evaluation.
   Evaluate against current state. Check an exact-version basis only when
   requested; let the application check declared domain assumptions.
4. CAS candidate, report receipt, accepted plan revision when changed, and next
   segment intent or wait together. A final report stores final acknowledgement
   instead. Allocate each successor identity once.
5. On duplicate ID and equal data, return the saved receipt without evaluation.
   On conflicting data, block the execution. Retain receipts across restart.
6. Map declared domain rejection codes to rejected receipts without a candidate
   commit. Release no proposed successor. Retain unexpected failures as pending
   reports for explicit repair and reconciliation. Settle a rejected final
   report without applying its result to domain state.
7. Run required hooks before successor release. A crash after receipt CAS must
   recover the saved next action; it must not repeat the reducer or planner.
8. Adapt ordinary delegated Action/Flow results to the final-report binding.
   Keep intermediate and final delivery on one logical protocol.

Exit evidence: `DUR-T06`, `DUR-T07`, `DUR-T10`, `DUR-T16`, `DUR-T17`, and
`DUR-T19`. Inject failure before and after every report, receipt, and successor
write. A committed report cannot lose its successor intent.

## Phase 6 - Add semantic waits and control input

Package: Core. Primary boundary: ContinueExecution, stored waits, input
receipts, cancellation, deadlines, and execution inspection.

1. Let a report commit a semantic wait and return AgentServer to idle. Keep no
   blocked worker or suspended callback for that wait.
2. Let an ordinary approval or correction Signal validate current domain state
   and return ContinueExecution with a trusted next Flow, wait ID, and input ID.
3. CAS candidate, consumed wait, input receipt, and next intent together.
   Use stable command IDs for duplicate control replies and input receipt
   lookup for inspection. A new command that repeats a consumed input ID
   rejects before candidate commit. Conflicting reuse and unknown waits reject.
   Preserve ordinary `call` return types. Do not add raw managed Runner input
   or a durable inbox.
4. Retain waits and deadlines through full instance restart. Consume a wait at
   most once. Capacity and receipt bounds apply before continuation release.
5. Make cancellation block pending reports and future segments. Preserve prior
   committed findings. Test cancellation against report commit and successor
   release in both orders. A wait can cancel without creating a Worker.
6. Reject hibernate, definition replacement, and delete while any execution is
   unacknowledged in this path. Retain explicit pruning and epoch-close rules.

Exit evidence: `DUR-T08`, `DUR-T12`, `DUR-T16`, and `DUR-T18`. A user correction
can change domain state while a graph runs; its next report checks the new goal
revision. This does not claim hot graph steering.

## Phase 7 - Add the AI DSL and trusted compiler

Package: `jido_ai`, in its own repository. Depends on approved public Core
contracts from Phases 2 through 6. Action and Runic stay fixed.

1. Implement the concrete research Agent declaration in the design as an
   authoring extension. Lower `ai(:research)` to an ordinary route target.
   Keep model, tool, plan, limit, report, and control declarations in AI.
2. Provide the same pure lowerer to data authors before Builder or Codec use.
   Verify canonical equality across module and data authoring. Store no Spark
   entities, clients, credentials, or functions in portable definitions.
3. Build a versioned catalog of trusted component and schema IDs. Reject
   unknown components, capabilities, ports, stop conditions, and limits before
   dispatch. Generated plans contain data, not generated Elixir modules.
4. Compile supported plans to runtime Flow values. Keep native map/reduce and
   graph dependencies visible in the executable graph. Keep code separate from
   runtime context. Use the Flow Codec and trusted Registry for storage.
5. Split only at declared semantic commit points. Compile an ordinary Flow
   segment for planning, investigation, review, or publication as needed.
   Do not force a segment per model/tool call or hide a graph inside an Action.
6. Persist the exact accepted plan and compiled document lineage. Recovery
   loads them; plan repair produces a new proposal and revision.
7. Record supported shapes and exclusions against the Flow gap register. Native
   persistent accumulators, live commit ports, and arbitrary graph targets
   remain excluded unless separate public API proofs close their gaps.

Exit evidence: `DUR-T14`, `DUR-T15`, `DUR-T17`, `DUR-T19`, and `DUR-T20`.
The AI package has no private AgentServer access or separate graph interpreter.

## Phase 8 - Establish effect policy and prove an adaptive Agent

Packages: AI for effect policy and the research example; Core for generic
runtime regression tests. Keep checks and changes scoped to their package.

1. Declare replay classes for every model/tool component. Confirm stable
   effect intent before provider I/O where idempotent replay is supported.
   Keep effect IDs stable across node replay. Test the crash after remote
   success but before local result storage.
2. Require provider idempotency or an explicit attention path for uncertain
   effects. A checkpoint alone does not establish safe replay. Block unsupported
   unsafe scopes instead of adding a Core per-node retry engine.
3. Exercise one Agent that proposes a data plan, runs a parallel investigation,
   publishes a finding, accepts a correction, records approval wait, restarts,
   consumes approval once, and commits a final report.
4. Update unrelated Agent state while a segment runs. Check that report commit
   preserves it and that stale goal assumptions reject as declared.
5. Inspect the actual Runic graph and productions. Distinguish transient
   progress, a stored report, an Agent commit receipt, and final completion.
6. Run an ordinary non-AI Agent with the same AgentServer implementation.
   Review the Core diff for model, tool, planning, review, and graph scheduling
   clauses. The expected count of those clauses is zero.

Exit evidence: `DUR-T19`, `DUR-T21`, and `DUR-T22`, plus all earlier groups.
Safe durable tool support is not claimed until its effect tests pass.

## Required acceptance groups

These are future acceptance tests, not reported results. Existing IDs retain
their original subject. `DUR-T12` changes its cardinality assertion because
`DUR-REQ-026` is explicitly retired.

| Group | Required evidence |
| --- | --- |
| DUR-T01 | Independent record/state versions; format migration; runtime envelope; incarnation/tombstone preservation; custom checkpoint safety |
| DUR-T02 | Crash around intent CAS; atomic candidate/receipt/intent; no work before accepted responsibility |
| DUR-T03 | Command duplicate/conflict; receipt lookup after timeout; capacity, closed epoch, and incarnation behavior |
| DUR-T04 | All target forms; manual start; admitted input checkpoint; build-only log; stable segment workflow ID; no private identity use |
| DUR-T05 | Worker/native replacement; AgentServer, Runner, RuntimeStore, and full instance restart; permit and version checks |
| DUR-T06 | Lost hint; failed checkpoint; persisted stop; stored result after restart; deferred-effect rejection |
| DUR-T07 | Final result against current state; crash around final receipt CAS; duplicates, forged acks, rejected final result, and failed completion reducer |
| DUR-T08 | Cancel before/during work and during wait; report/release races; no external rollback claim; caller timeout; restored deadline |
| DUR-T09 | CAS conflict, rejection, uncertain acknowledgement; identical snapshot reconciliation; one writer; postponed write wake-up |
| DUR-T10 | Required hook order and failure; uncertain hook window; no automatic hook replay or successor release before hook gate |
| DUR-T11 | Portability; registry/deployment mismatch; artifact/report/record sizes; complete log and Flow Codec round trips |
| DUR-T12 | Multiple behavior keys; same-key rejection; finite active capacity; bounded receipts/history; prune and stale identity; lifecycle rejection |
| DUR-T13 | Attached owner death during start, work, and cleanup; native scope stop; late results; unchanged caller/Turn timeout semantics |
| DUR-T14 | Proposed Agent DSL; canonical module/data/Builder/Codec parity; validation diagnostics; no source-only entities in documents |
| DUR-T15 | Runtime AI plan becomes an inspected native Flow graph; map/reduce fan-out/fan-in; trusted catalog and limit rejection |
| DUR-T16 | Intermediate report protocol; atomic receipt/successor; duplicates/conflicts; domain and exact-version basis; rejection, failure, forged delivery, and nonempty Directive rejection |
| DUR-T17 | Exact accepted plan and graph retained before effectful release; versioned repair; restart with no planner rerun |
| DUR-T18 | Wait without blocked worker; ordinary approval Signal; input dedup; consumed wait; unrelated Turns; full restart |
| DUR-T19 | One authoritative domain state; workflow working state; current-state reduction; progress is not a commit receipt |
| DUR-T20 | Outcome for every Flow gap; fixed Action/Runic revisions and diffs; no opaque runner Action or private API bypass |
| DUR-T21 | Complete adaptive research path and ordinary non-AI path through the same AgentServer; no AI-specific transition clauses |
| DUR-T22 | Replay declarations; effect intent before provider I/O; stable effect ID; uncertain external success blocks unsafe recovery |

Use barriers and monitors for crash tests. Inject failure at each named
checkpoint, Agent CAS, hook release, input receipt, and successor dispatch.
Elapsed sleeps are not evidence that a write or stop occurred.

## Final verification and human review

When implementation is authorized and complete, run focused groups after each
slice, then run from `jido/`:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test.all
mix test.persistence
mix quality
```

Run the AI package's own required checks from `jido_ai/` after its phases. Test
Core first when both change. Use documented service-backed adapter checks
where the advertised durability scope requires them. Record unavailable
services as unverified. Do not report checks from another revision as current.

Before human review:

- Compare Action and Runic revisions, status, and diffs with the fixed baseline.
- List source changes and test evidence separately for Core and AI.
- Keep code and tests out of this documentation revision.
- Confirm no duplicate graph scheduler, generic Directive replay log, unsafe
  recovery bypass, or distributed ownership claim entered Core.
- Report every open Flow gap, current baseline failure, and recovery limit.
- Leave implementation changes uncommitted unless the user later requests a
  commit.

## Simplification test

The design passes when there is one owner per decision: Core commits Agent
state and accepted work; AI compiles behavior and owns AI policy; Runic advances
graphs; the Store confirms persistence. Core records semantic handoffs, not
model loops or node scheduling.

Count AgentServer responsibilities and transitions, not only lines of code.
Every new helper has one named protocol boundary and failure test. Moving a
second graph interpreter into a helper is not simplification. A segment
boundary is justified by a state commit or external wait, not by a model call.
