> Gap analysis. This document is pending approval.

# Agent Server gap analysis

## Scope and owner

This report covers only the Agent Server seam. The seam owns one live Agent
process, Signal admission, active Turn control, live committed state, commit
coordination, Directive settlement, cancellation, runtime inspection, and the
failure boundary of that process. The main design source is
`docs/design/08_agent-server/agent-server.md`. The code under `lib` is the
source of truth for current behavior.

This report also checks direct contracts with the Turn Evaluator, Plugin
runtimes, persistence, the Jido instance facade, errors, and observability. It
does not review those subsystems in general.

The design is a deferred proposal and is pending approval
(`docs/design/08_agent-server/agent-server.md:1-2`). Therefore, statements in
the design are proposals unless current code and tests implement them.

## Implemented baseline

The following items are current facts.

- `Jido.AgentServer` is a `:gen_statem` process. Its implemented states are
  `:initializing`, `:idle`, `:admitting`, `:running`, and `:directing`
  (`lib/jido/agent_server.ex:2-10`, `lib/jido/agent_server.ex:499-500`,
  `lib/jido/agent_server.ex:1382-1383`).
- Startup restores an Agent first, validates it, starts Plugin children, waits
  for Plugin readiness, and then reports readiness. It does not write a new
  persistent record during this startup sequence
  (`lib/jido/agent_server.ex:438-500`, `lib/jido/agent_server.ex:506-544`).
- One `ActiveTurn` holds a UUID7 Turn ID, source and effective Signal structs,
  caller, execution handle, prepared command, Turn context, versions,
  Directive counts, and telemetry spans
  (`lib/jido/agent_server/active_turn.ex:8-57`).
- Plugin admission runs in a supervised task. The Server uses
  `directive_timeout` as the admission-task timeout
  (`lib/jido/agent_server.ex:1370-1383`). Executable work then runs through
  `Jido.Exec.run_async/4` or an execution adapter
  (`lib/jido/agent_server.ex:1419-1466`).
- Candidate finalization and Directive-list validation occur before commit
  (`lib/jido/agent_server.ex:1469-1490`). A successful commit increments
  `state_version` once. It writes either an instance runtime checkpoint or the
  configured persistence adapter before it swaps the live Agent
  (`lib/jido/agent_server.ex:1493-1527`,
  `lib/jido/agent_server.ex:2907-2929`).
- The Signal caller receives `{:ok, agent}` at commit. Directive work continues
  later in list order. A Directive failure does not roll back the committed
  Agent (`lib/jido/agent_server.ex:1529-1545`,
  `lib/jido/agent_server.ex:1725-1764`).
- Calls and casts that arrive while work is active use OTP postponement. The
  Server keeps a bounded token set, rejects excess calls, and drops excess
  casts with a log entry (`lib/jido/agent_server.ex:1926-1978`). The module
  documentation correctly states that this does not bound messages that have
  not reached the state-machine callback (`lib/jido/agent_server.ex:17-20`).
- Cancellation is implemented for Plugin admission and executable work.
  Current results are raw values such as `:cancelled`, `:idle`, `:directing`,
  and `:stale_turn` (`lib/jido/agent_server.ex:709-756`,
  `lib/jido/agent_server.ex:1596-1637`). A failed executable cancellation stops
  the Server as indeterminate (`lib/jido/agent_server.ex:1609-1619`).
- The current public module documentation exposes direct Agent Server
  operations for calls, casts, asynchronous requests, cancellation,
  inspection, debug events, owner attachment, child control, snapshots, and
  hibernation (`lib/jido/agent_server.ex:85-393`).
- Current `status/2` returns an unvalidated map. It includes the phase, Agent
  ID, state version, admission data, lifecycle data, child data, error count,
  and a small active-Turn map (`lib/jido/agent_server.ex:1878-1924`). Current
  `snapshot/2` returns `%{agent: agent, state_version: version}`
  (`lib/jido/agent_server.ex:614-620`).
- Current error policy supports `:log_only`, `:stop_on_error`,
  `{:max_errors, count}`, `{:emit_signal, dispatch}`, and an application
  function of arity two (`lib/jido/agent_server/options.ex:303-325`). The
  application function executes in the Agent Server process
  (`lib/jido/agent_server.ex:2561-2570`).
- A nonpersistent supervised Server saves each commit in `RuntimeStore` and
  restores it after an abnormal restart
  (`lib/jido/agent_server/runtime_checkpoint.ex:8-43`,
  `lib/jido/agent_server.ex:2882-2884`). A clean shutdown deletes this runtime
  checkpoint (`lib/jido/agent_server.ex:2954-2955`).
- The current Outcome is a validated public struct. Its control stages are
  `:prepare`, `:execute`, `:finalize`, `:commit`, and `:directive`. It contains
  complete source and effective Signal structs and a nested Directive summary
  (`lib/jido/agent/turn/outcome.ex:13-67`).

## Aligned contracts

The following design contracts agree in substance with current behavior.

- The Server serializes Signals and has at most one active Turn. Later Signals
  are postponed until the active work settles. Tests confirm sender-order
  processing and responsive inspection during executable work
  (`test/jido/agent_server/public_api_test.exs:269-331`).
- Plugin readiness gates initial admission. Startup failure and readiness
  timeout stop and clean up provisional runtime work
  (`lib/jido/agent_server.ex:506-568`,
  `test/jido/agent_server/plugin_lifecycle_test.exs:82-108`).
- Candidate Agent state and the complete Directive list are validated before
  the live state changes. A pre-commit failure preserves Agent state and
  version (`lib/jido/agent_server.ex:1469-1507`,
  `test/jido/agent_server/public_api_test.exs:372-441`).
- One successful Turn advances the state version once, including an
  equal-state result. The committed Agent is visible before post-commit
  Directives finish (`lib/jido/agent_server.ex:1493-1545`,
  `test/jido/agent_server/directive_execution_test.exs:119-131`).
- Directive work runs after commit, in separate bounded tasks where needed.
  A failure keeps the commit and records exact progress in the current Outcome
  (`lib/jido/agent_server.ex:1639-1862`,
  `test/jido/agent_server/directive_execution_test.exs:134-223`).
- A caller wait timeout does not cancel executable work that has started
  (`lib/jido/agent_server.ex:180-186`,
  `test/jido/agent_server/public_api_test.exs:333-345`).
- The Server detects synchronous reentry from executable, admission, and
  Directive task trees (`lib/jido/agent_server.ex:795-839`,
  `lib/jido/agent_server.ex:1981-2008`).
- A Plugin runtime can restart from current committed Plugin state while the
  Agent Server stays responsive
  (`test/jido/agent_server/runtime_lifecycle_test.exs:225-290`). Loss of the
  Plugin lifecycle owner causes the Agent Server to stop and restart from its
  current checkpoint (`lib/jido/agent_server.ex:2188-2191`,
  `test/jido/agent_server/runtime_lifecycle_test.exs:293-326`).

## Gaps

### Missing implementation

These items exist in the proposed design but not in current code.

1. **The Ref-first live Agent facade is not implemented.** The generated
   instance facade has startup, PID-or-ID stop, lookup, list, hibernate, and
   thaw functions. It does not have `agent_ref/2`, `activate_agent/2`,
   `call/3`, `cast/3`, asynchronous Signal operations, cancellation,
   Ref-first inspection, `commit/2`, `plugin_runtimes/2`, or `delete_agent/2`
   (`lib/jido.ex:144-185`). The proposal requires these operations and makes
   them the only public live Agent API
   (`docs/design/08_agent-server/agent-server.md:124-150`,
   `docs/design/09_jido-instance/jido-instance.md:130-176`).
2. **There is no Server-owned `turn_timeout`.** The option is absent from
   `Jido.AgentServer.Options` and `Jido.AgentServer.State`
   (`lib/jido/agent_server/options.ex:11-58`,
   `lib/jido/agent_server/state.ex:4-74`). Native `Jido.Exec` work has no
   Server evaluation timer. A custom execution adapter uses
   `directive_timeout` for each adapter callback instead
   (`lib/jido/agent_server.ex:1440-1466`,
   `lib/jido/agent_server/execution_adapter.ex:21-40`).
3. **There is no instance `persistence_timeout` boundary.** Persistence calls
   run synchronously in the state-machine callback. `Jido.Persistence.protect/2`
   catches faults but applies no time limit
   (`lib/jido/agent_server.ex:1493-1507`,
   `lib/jido/persistence.ex:79-99`, `lib/jido/persistence.ex:410-416`).
4. **Persistent creation does not write the initial version-zero record.** The
   Server reports startup success immediately after Plugin readiness. It first
   writes persistent Agent state only on a Turn commit, hibernate, or clean
   stop (`lib/jido/agent_server.ex:517-533`,
   `lib/jido/agent_server.ex:2907-2949`). The proposed initial durable boundary
   requires readiness, an initial Commit, a create-only write, and only then
   publication (`docs/design/07_persistence/instance-persistence.md:146-173`).
5. **The proposed public inspection values do not exist.** There are no
   `Jido.Agent.Status`, `Jido.Agent.Turn.Status`, or `Jido.Agent.Commit`
   modules. Current inspection returns maps and a `snapshot/2` result instead
   (`lib/jido/agent_server.ex:257-263`,
   `lib/jido/agent_server.ex:381-389`,
   `lib/jido/agent_server.ex:1878-1924`).
6. **The proposed stable control errors are not implemented at this seam.**
   Cancellation and admission return raw atoms or tuples. They do not return
   `Jido.Error.RuntimeError` values with `:turn_cancelled`,
   `:no_active_turn`, `:turn_mismatch`, or `:too_late`
   (`lib/jido/agent_server.ex:709-756`,
   `lib/jido/agent_server.ex:784-787`,
   `docs/design/12_errors-and-contracts/errors.md:79-89`).

### Design/code conflict

These current behaviors directly conflict with the proposed design.

1. **The phase model differs.** The proposal says that there are four phases
   and includes Plugin preparation in `:running`. Current code and tests expose
   a fifth stable-looking phase, `:admitting`
   (`docs/design/08_agent-server/agent-server.md:67-76`,
   `lib/jido/agent_server.ex:5-10`,
   `test/jido/agent_server/context_test.exs:89-111`).
2. **The control-stage model differs.** The proposal exposes only
   `:evaluate`, `:commit`, and `:directive`. Current Outcome and tests expose
   `:prepare`, `:execute`, and `:finalize` as separate public stages
   (`docs/design/08_agent-server/agent-server.md:92-100`,
   `lib/jido/agent/turn/outcome.ex:13-15`,
   `test/jido/agent/turn/outcome_test.exs:24-53`). Current status has no active
   stage at all (`lib/jido/agent_server.ex:1913-1923`).
3. **The direct Agent Server API is public in code.** The proposal permits
   only internal OTP start contracts and says that a PID has no supported
   command API. Current public documentation and tests directly support the
   PID/name API (`docs/design/08_agent-server/agent-server.md:14-22`,
   `docs/design/08_agent-server/agent-server.md:143-145`,
   `lib/jido/agent_server.ex:85-393`,
   `test/jido/agent_server/public_api_test.exs:87-120`).
4. **Nonpersistent restart semantics differ.** The proposal says that a
   nonpersistent restart resets to an `initial_agent` kept in the child
   specification. Current state has no `initial_agent`; it restores the latest
   commit from `RuntimeStore`. The current module documentation states that
   this checkpoint prevents restart from old initialization data
   (`docs/design/08_agent-server/agent-server.md:41-65`,
   `lib/jido/agent_server/state.ex:4-74`,
   `lib/jido/agent_server.ex:28-32`,
   `lib/jido/agent_server/runtime_checkpoint.ex:8-34`).
5. **Persistence failure policy differs.** The proposal says that every
   persistence write error stops the Server with lost write authority. Current
   code stops only for errors classified as uncertain. A normal adapter error
   goes through the configurable error policy, whose default continues
   (`docs/design/08_agent-server/agent-server.md:223-236`,
   `lib/jido/agent_server.ex:1548-1585`). A test confirms that a failed write
   keeps old state and exposes no Directive work, but it does not expect the
   Server to stop (`test/jido/agent_server/effect_recovery_test.exs:176-189`).
6. **Error policy is open and executable.** The proposal limits policy to
   closed `:continue` or `:stop` data and says that it cannot emit a Signal or
   run application code. Current code accepts an application function and an
   `{:emit_signal, dispatch}` policy
   (`docs/design/08_agent-server/agent-server.md:169-180`,
   `lib/jido/agent_server/options.ex:303-325`,
   `lib/jido/agent_server.ex:2532-2598`).
7. **Admission uses the Directive timeout.** The proposal separates admission
   deadline, Turn timeout, persistence timeout, and Directive timeout. Current
   Plugin admission is cancellable but uses `directive_timeout` as its work
   timer and reports a Plugin admission timeout
   (`docs/design/08_agent-server/agent-server.md:96-105`,
   `lib/jido/agent_server.ex:947-962`,
   `lib/jido/agent_server.ex:1370-1383`).
8. **Outcome shape and data limits differ.** The proposal uses Agent Ref and
   Signal identities and says that an Outcome contains no Signals or payloads.
   The current Outcome stores complete source and effective Signal structs,
   uses `id` and `agent_id`, and uses a nested Directive summary
   (`docs/design/08_agent-server/agent-server.md:300-331`,
   `lib/jido/agent/turn/outcome.ex:16-63`).
9. **A per-Server debug timeline exists.** The proposal and observability seam
   say that no such buffer exists. Current state has `debug_events`, and public
   functions enable and read it
   (`docs/design/08_agent-server/agent-server.md:333-335`,
   `docs/design/13_observability/observability.md:29-37`,
   `lib/jido/agent_server/state.ex:50-55`,
   `lib/jido/agent_server.ex:283-292`).
10. **Turn telemetry starts before Plugin admission.** The observability design
    says that the Turn span starts after admission. Current code starts the
    semantic Turn span before it creates the Plugin admission task
    (`docs/design/13_observability/observability.md:90-94`,
    `lib/jido/agent_server.ex:1285-1305`).
11. **Cancellation results differ.** The proposal uses `:no_active_turn`,
    `:turn_mismatch`, and `:too_late`, with a `:turn_cancelled` error for the
    active request. Current code uses `:idle`, `:directing`, `:stale_turn`, and
    `:cancelled` (`docs/design/08_agent-server/agent-server.md:214-217`,
    `lib/jido/agent_server.ex:709-756`,
    `lib/jido/agent_server.ex:1596-1637`). Current code also permits
    cancellation during the separate Plugin admission phase.

### Missing decision

These are decisions that must be explicit before implementation starts.

1. Decide whether the five current runtime phases are private implementation
   states or public status values. If `:admitting` stays private, define how
   public status maps it to `:running` and which stage it reports.
2. Decide the exact evaluation timeout scope. The proposal groups routing,
   Plugin admission and preparation, executable evaluation, Plugin
   contribution, and candidate validation under `turn_timeout`. The current
   code starts different asynchronous units at different times. Specify one
   timer start point and one cancellation procedure for all of them.
3. Decide whether cancellation includes Plugin admission. If it does, define
   whether this is part of `:evaluate` and uses the same `:turn_cancelled`
   result. If it does not, define the supported control result during
   admission.
4. Decide whether the current PID API has a compatibility period. The design
   must state which direct `Jido.AgentServer` functions become private, which
   remain OTP supervision tools, and whether any deprecated wrappers remain.
5. Decide whether current `RuntimeStore` checkpoints are an intentional
   non-durable restart feature. This behavior conflicts with the proposed
   reset-to-initial contract and with the Jido instance rule at
   `docs/design/09_jido-instance/jido-instance.md:207-210`.
6. Decide whether a confirmed persistence conflict also removes write
   authority. The persistence design says that every write error stops the
   Server (`docs/design/07_persistence/instance-persistence.md:208-216`). The
   current Agent Server documentation says that the configured error policy
   handles a conflict (`lib/jido/agent_server.ex:172-178`).
7. Decide the terminal Directive failure rule. The Agent Server proposal says
   that a Directive failure applies error policy, but it also says that
   Directive failures have fixed stop behavior
   (`docs/design/08_agent-server/agent-server.md:117-119`,
   `docs/design/08_agent-server/agent-server.md:174-180`). These two statements
   do not define one result.
8. Decide whether the Outcome is a bounded identity projection or a diagnostic
   record with full Signals. This choice also fixes the telemetry payload and
   redaction contract.
9. Decide whether `call/3` success means only durable commit or both durable
   commit and runtime-checkpoint success for a nonpersistent Agent. Current
   code makes `RuntimeStore.put/4` part of every nonpersistent commit
   (`lib/jido/agent_server.ex:2907-2909`).

### Missing verification

The following proposed contracts have no matching tests because the related
implementation is absent or different.

1. No test proves a whole-evaluation `turn_timeout`, task termination, late
   result rejection, unchanged committed state, and one timed-out Outcome.
2. No test proves a persistence callback timeout, an indeterminate public
   error, no Directive start, `:lost_write_authority`, and later explicit
   activation from the authoritative Record.
3. No test proves the persistent create sequence: provisional Plugin readiness,
   version-zero create-only write, publication after the write, duplicate
   Record rejection, and cleanup after a failed or indeterminate initial write.
4. No test covers all Ref-first facade operations, Ref resolution, partition
   checks, public error normalization, or rejection of PID command use.
5. No test validates the proposed `Jido.Agent.Status`,
   `Jido.Agent.Turn.Status`, and `Jido.Agent.Commit` schemas or their
   cross-field rules.
6. Current cancellation tests cover successful cancellation, stale IDs, and
   failed cancellation (`test/jido/agent_server/public_api_test.exs:447-520`).
   No deterministic test exercises both event orders in the cancellation versus
   result race at the commit boundary.
7. No test proves the proposed stable cancellation error codes and shaped
   `Jido.Error.RuntimeError` values.
8. No test proves that the proposed Outcome and telemetry exclude Signal and
   Directive payloads. The current Outcome tests require full Signal structs
   instead (`test/jido/agent/turn/outcome_test.exs:106-127`).
9. No test proves that a nonpersistent abnormal restart resets to the initial
   Agent. Current tests prove the opposite behavior for a required Plugin
   lifecycle failure (`test/jido/agent_server/runtime_lifecycle_test.exs:293-326`).
10. No test proves the proposed absence of a per-Server debug buffer. Current
    public API tests use that buffer to inspect terminal Outcomes
    (`test/jido/agent_server/public_api_test.exs:447-484`).

## Narrow dependency notes

These are current facts about direct seams.

- **Turn Evaluator:** The Server uses `Jido.Agent.Command.Runner.prepare/4`
  before asynchronous execution and `finish_for_server/2` after execution
  (`lib/jido/agent_server.ex:1419-1429`,
  `lib/jido/agent_server.ex:1469-1481`). The three proposed public control
  stages must hide these internal `:prepare`, `:execute`, and `:finalize`
  steps without removing useful error classification.
- **Plugins:** Plugin admission, outbound Signal preparation, and owned
  Directive dispatch can all call runtime processes. The Server must stay
  responsive while those calls wait. Current code uses supervised tasks for
  these paths (`lib/jido/agent_server.ex:1370-1383`,
  `lib/jido/agent_server.ex:1657-1709`,
  `lib/jido/agent_server.ex:1767-1825`). Any common Turn timer must cover these
  tasks without making post-commit Directive work cancellable.
- **Persistence:** Current persistence stores a revisioned Agent record through
  `Jido.Persistence.save_agent/3`, not the proposed public Record and Commit
  values (`lib/jido/persistence.ex:59-99`). The Agent Server cannot implement
  initial durable creation, lifecycle status, or lost-write-authority rules
  alone. It needs the persistence seam and instance timeout contract.
- **Jido instance:** Current startup returns a PID and current lookup returns a
  PID (`lib/jido.ex:431-480`, `lib/jido.ex:530-553`). The proposed Agent Ref is
  an instance-owned address. The facade and Server boundary must change
  together.
- **Errors:** Current Server operations leak atoms, tuples, and adapter errors.
  The proposed facade must convert them to the stable Splode error classes and
  codes before they cross the public boundary
  (`docs/design/12_errors-and-contracts/errors.md:115-130`,
  `docs/design/12_errors-and-contracts/errors.md:160-172`).
- **Observability:** Current telemetry and debug data use the current Outcome
  shape and five internal stages. The proposed bounded three-stage contract
  must be applied to telemetry at the same time as the Outcome change
  (`docs/design/13_observability/observability.md:39-73`,
  `docs/design/13_observability/observability.md:116-134`).

## Ordered recommendations

The following items are proposals, not current behavior.

1. **Approve one contract baseline.** Resolve the missing decisions above. In
   particular, lock the public facade, phase projection, three control stages,
   restart source, persistence failure rule, Directive failure rule, and
   Outcome data limit before runtime work starts.
2. **Build the Ref-first instance boundary.** Add Agent Ref creation and
   resolution. Add the required command, control, lifecycle, and inspection
   functions to generated instance modules. Keep only required supervision
   functions public in `Jido.AgentServer`. Add a documented compatibility plan
   for current PID callers.
3. **Add explicit control state.** Store the current public stage and all task,
   monitor, and timer identities in the active Turn. Map private preparation
   states to `:evaluate`. Set `:commit` before any write or live state swap.
4. **Implement distinct time budgets.** Add `turn_timeout` for the complete
   pre-commit evaluation unit, keep caller admission deadlines separate, use
   `directive_timeout` only for each post-commit Directive, and add an instance
   `persistence_timeout` around every write.
5. **Implement the durable creation and authority rules.** Create the initial
   Record only after Plugin readiness. Stop on every failed persistent write,
   classify timeout as indeterminate, start no Directive, and require explicit
   activation after write authority is lost.
6. **Replace current inspection and Outcome projections.** Add the public Zoi
   structs, return `Jido.Agent.Commit` instead of a snapshot map, and remove
   complete Signals and payloads from the public Outcome and telemetry.
7. **Close and normalize failure policy.** Replace executable error callbacks
   and error-Signal policy with approved closed data. Return the stable
   cancellation and timeout errors through the instance facade. Keep internal
   shutdown reasons out of public command results.
8. **Remove or reclassify the debug buffer.** If it remains, update the design
   and define its security and compatibility status. If the design remains as
   written, remove the per-Server buffer and use bounded telemetry and status.
9. **Add seam tests before migration is complete.** Cover each missing
   verification item. Use deterministic workers and gates for timeout,
   cancellation race, write-authority, and startup-order tests. Keep current
   behavior tests only when that behavior is an approved compatibility
   contract.

## Evidence index

The principal evidence is grouped here for quick review.

- Proposed Server boundary and ownership:
  `docs/design/08_agent-server/agent-server.md:12-35`.
- Proposed phases, stages, and timeouts:
  `docs/design/08_agent-server/agent-server.md:67-122`.
- Proposed facade, options, and control results:
  `docs/design/08_agent-server/agent-server.md:124-221`.
- Proposed failure and inspection contracts:
  `docs/design/08_agent-server/agent-server.md:223-335`.
- Current public Server contract: `lib/jido/agent_server.ex:82-430`.
- Current state machine and admission: `lib/jido/agent_server.ex:432-963` and
  `lib/jido/agent_server.ex:1285-1467`.
- Current commit, cancellation, and Directive settlement:
  `lib/jido/agent_server.ex:1469-1862`.
- Current status, overload, and reentry behavior:
  `lib/jido/agent_server.ex:1878-2008`.
- Current error policy and Outcome settlement:
  `lib/jido/agent_server.ex:2504-2648`.
- Current restore and persistence behavior:
  `lib/jido/agent_server.ex:2874-2955`.
- Current runtime data types: `lib/jido/agent_server/state.ex:4-79`,
  `lib/jido/agent_server/active_turn.ex:8-129`, and
  `lib/jido/agent/turn/outcome.ex:13-190`.
- Current options and validation: `lib/jido/agent_server/options.ex:7-134` and
  `lib/jido/agent_server/options.ex:294-402`.
- Current focused tests: `test/jido/agent_server/public_api_test.exs`,
  `test/jido/agent_server/context_test.exs`,
  `test/jido/agent_server/directive_execution_test.exs`,
  `test/jido/agent_server/plugin_lifecycle_test.exs`,
  `test/jido/agent_server/runtime_lifecycle_test.exs`, and
  `test/jido/agent/turn/outcome_test.exs`.
