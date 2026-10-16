---
modules:
  - Jido.AgentServer2
  - Jido.AgentServer2.Activation
---

## Purpose

Protect only the AgentServer2 prototype and its current public behavior.
The implementation remains in one file. Pending, Store, and Activation are internal helpers.
Shared Ref facade routing is covered only for coexistence with this runtime.
Existing AgentServer implementation and distributed behavior are outside this component. Required durable saves, restore, and Plugin reconstruction are protected through the existing persistence APIs.

## Obligations

### jido.agent_server2.I1 — Startup validation

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Start only with a complete Agent instance and a live named Runner with the temporary Store, including the shared instance Store. Reject invalid options, definitions, and unrelated or stale Runner names. Enforce instance Runner ownership.
- **why:** Invalid startup must not create an activation.
- **kind:** functional
- **status:** active

### jido.agent_server2.I2 — Runtime defaults

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Use a 60000 ms built-in turn timeout and the declared built-in runtime defaults. Read valid application turn_timeout defaults at startup; do not accept other application runtime defaults. Explicit values override unused application configuration. Reject unknown configuration keys and finite waits outside 0..4294967295. Name each invalid timeout field in its validation error.
- **why:** Configuration errors must be detected before work starts.
- **kind:** functional
- **status:** active

### jido.agent_server2.I3 — Signal validation

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.cast/3`
- **must:** Reject malformed Signals before execution. Preserve the committed Agent and revision and keep the activation alive.
- **why:** Bad input must not destroy live state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I4 — Transient context

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.cast/3`
- **must:** Pass supported map, keyword, or nil context to the turn. Reject unknown options and reserved keys. Keep transient values out of Agent state and Signal data.
- **why:** Runtime input must not become domain state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I5 — Responsive committed reads

- **scope:** `Jido.AgentServer2.agent/1`, `Jido.AgentServer2.status/1`
- **must:** Return committed state and a bounded status while a turn or cleanup is active. Report Agent identity, active turn and Signal IDs, starting revision, stage, and queue counts. Separate reads are not atomic.
- **why:** Inspection must remain available without exposing input or internal request handles.
- **kind:** functional
- **status:** active

### jido.agent_server2.I6 — Serial execution

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.cast/3`
- **must:** Run at most one turn per activation. Queued work starts from the previous committed result.
- **why:** Turns must not overwrite each other.
- **kind:** functional
- **status:** active

### jido.agent_server2.I7 — One commit

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.status/1`
- **must:** Commit the complete validated candidate once on success and increment the runtime revision once, including successful unchanged state.
- **why:** Completion must have one commit boundary.
- **kind:** functional
- **status:** active

### jido.agent_server2.I8 — Failure isolation

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`
- **must:** Action or Flow failure, routing failure, or invalid candidate preserves the complete committed Agent and revision. Ordinary failure permits later work under the default policy.
- **why:** Rejected work must not corrupt state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I9 — Returned directives

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`
- **must:** Validate the complete supported batch before commit. Return directives with commit success, then run them in order before the next turn.
- **why:** Execution and effects have separate owners.
- **kind:** functional
- **status:** active

### jido.agent_server2.I10 — Pending replies

- **scope:** `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.await/2`
- **must:** Return a temporary handle without waiting for turn completion. Only the submitting process can collect it. Wait timeout returns an error and permits a later wait without cancelling work.
- **why:** Asynchronous requests need explicit reply ownership.
- **kind:** functional
- **status:** active

### jido.agent_server2.I11 — Caller wait

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.cancel/2`
- **must:** Caller wait timeout exits as an OTP call does. It does not cancel accepted turn work or revoke accepted cancellation.
- **why:** Waiting and execution have separate limits.
- **kind:** functional
- **status:** active

### jido.agent_server2.I12 — Reply disposal

- **scope:** `Jido.AgentServer2.abandon/1`
- **must:** Only the submitting process can discard a pending reply. Remove its monitor, discard a queued reply, and prevent late replies without cancelling the turn.
- **why:** Unwanted replies must not retain Agent values in the caller mailbox.
- **kind:** functional
- **status:** active

### jido.agent_server2.I13 — Casts

- **scope:** `Jido.AgentServer2.cast/3`
- **must:** Accept a valid cast without a result handle. Apply the same turn validation and commit rules. Dropped or failed casts do not change committed state.
- **why:** Best-effort requests still require state safety.
- **kind:** functional
- **status:** active

### jido.agent_server2.I14 — Queue capacity

- **scope:** `Jido.AgentServer2.start_link/1`, `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.cast/3`
- **must:** Bound postponed turns separately from the active turn and mailbox. Reject excess requests with limit and count; drop excess casts. Support zero and infinity.
- **why:** Admission must have a clear capacity limit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I15 — Admission expiry

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`
- **must:** Reject expired requests before execution, including replay of queued work. Zero always expires. An admission deadline does not stop a turn that already started.
- **why:** Queued work must retain its own admission budget.
- **kind:** functional
- **status:** active

### jido.agent_server2.I16 — Owned requests

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`, `Jido.AgentServer2.cancel/2`, `Jido.AgentServer2.cancel_turn/3`
- **must:** Reject direct and nested OTP Task requests from detected owned work with reentrant_turn, including execution startup. Allow unrelated callers even if an Action monitors them. Reads remain available. Detection follows local caller ancestry to depth eight, not arbitrary process protocols.
- **why:** A turn must not wait for itself or cancel its own execution.
- **kind:** functional
- **status:** active

### jido.agent_server2.I17 — Whole-turn deadline

- **scope:** `Jido.AgentServer2.start_link/1`, `Jido.AgentServer2.await/2`
- **must:** Apply the active timeout to preparation, startup, execution, candidate validation, and cleanup. Recheck before commit. Zero cannot commit; infinity disables the active deadline. Reply with turn_timeout only after cleanup.
- **why:** A delayed timer must not permit a late commit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I18 — Cancellation

- **scope:** `Jido.AgentServer2.cancel/2`
- **must:** Stop active owned work, preserve committed state and revision, and return ok only after cleanup. The turn receives cancelled. Idle cancellation and cancellation after commit during effects or after terminal cleanup during failure policy return not_running. Repeated cancellation shares cleanup; the first abort reason wins.
- **why:** Cancellation must have a confirmed ownership boundary.
- **kind:** functional
- **status:** active

### jido.agent_server2.I19 — Targeted cancellation

- **scope:** `Jido.AgentServer2.cancel_turn/3`
- **must:** Cancel only the matching active turn ID. Reject a stale ID without affecting current work. Keep one active ID through the turn.
- **why:** An old request must not cancel newer work.
- **kind:** functional
- **status:** active

### jido.agent_server2.I20 — Successful cleanup

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.submit/3`
- **must:** Confirm Worker and execution Task cleanup before success and before the next turn. Do not retain execution records in the temporary Store, including the shared instance Store.
- **why:** Successful turns must not accumulate execution resources.
- **kind:** functional
- **status:** active

### jido.agent_server2.I21 — Abort cleanup

- **scope:** `Jido.AgentServer2.cancel/2`, `Jido.AgentServer2.cancel_turn/3`
- **must:** Confirm cleanup after timeout or cancellation at preparation, Worker startup, execution, and validation. Fence in-flight Worker startup before admitting later work. Keep reads available during cleanup.
- **why:** An aborted startup must not leave detached execution.
- **kind:** functional
- **status:** active

### jido.agent_server2.I22 — Server ownership

- **scope:** `Jido.AgentServer2.stop/3`
- **must:** Stop owned Worker and Action work after explicit stop or abrupt server death. Preserve standard clean shutdown reasons.
- **why:** Execution must not outlive its owner.
- **kind:** functional
- **status:** active

### jido.agent_server2.I23 — Lifecycle loss

- **scope:** `Jido.AgentServer2.await/2`
- **must:** Stop the activation when its Runner, Worker, or lifecycle Task is lost, or cleanup cannot be confirmed. Do not commit a candidate or start queued work after ownership becomes uncertain.
- **why:** Unknown execution ownership cannot be treated as safe completion.
- **kind:** functional
- **status:** active

### jido.agent_server2.I24 — Late messages

- **scope:** `Jido.AgentServer2.status/1`, `Jido.AgentServer2.cancel_turn/3`
- **must:** Ignore stale completion and timeout messages. A discarded result cannot commit or affect a later turn.
- **why:** Mailbox races must not cross turn boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I25 — Safe failure logs

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.cast/3`
- **must:** Return Action or Flow errors to the caller without raw Runner failure warnings containing node input or error values. Failed casts retain an Agent and turn ID summary. This does not filter logs written by application code.
- **why:** Runtime failure reporting must not expose private input.
- **kind:** functional
- **status:** active

### jido.agent_server2.I26 — Policy validation

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Reject unknown execution keys, invalid timeouts, attempts, backoff, concurrency, hook arities, error policies, unbounded policy waits, and invalid history limits before startup.
- **why:** Runtime policy must be valid before execution starts.
- **kind:** functional
- **status:** active

### jido.agent_server2.I27 — Eligible bounded retries

- **scope:** `Jido.AgentServer2.call/3`
- **must:** Use the owned Runner for per-node timeouts and retries. Run at most max_attempts attempts, retry only retryable Action errors, apply configured backoff, and let the outer deadline or cancellation stop retry work.
- **why:** Retries must not bypass ownership, error classification, or the commit boundary.
- **kind:** functional
- **status:** active

### jido.agent_server2.I28 — Execution scheduling and hooks

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Apply max_concurrency to Flow nodes within one serial turn. Compose supported Worker hooks with ownership, trace propagation, and safe runtime failure logging.
- **why:** Execution policy must not change turn isolation.
- **kind:** functional
- **status:** active

### jido.agent_server2.I29 — One terminal summary

- **scope:** `Jido.AgentServer2.status/1`
- **must:** Record one terminal summary for each admitted turn: succeeded, failed, cancelled, timed_out, or indeterminate. Report stage, commit indicator, versions, IDs, directive count, and duration without raw state, input, or errors. Emit one settled event when the process can run its terminal callback; an untrappable kill cannot emit it.
- **why:** Observers need one safe statement of the commit result.
- **kind:** functional
- **status:** active

### jido.agent_server2.I30 — Failure decisions

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Default to continuing after ordinary failure. Support stop_on_error and a consecutive max_errors threshold; success resets the count. Stop decisions preserve the original error reply.
- **why:** Failure policy must not alter committed domain state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I31 — Bounded custom failure policy

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Run custom error callbacks outside the server with a finite policy deadline after terminal cleanup. Keep reads available and reject owned reentrant turns. Serialize queued work until the decision. Stop safely on timeout, exception, invalid return, or callback failure and preserve the original turn error.
- **why:** Policy work must not block reads or revise a terminal outcome.
- **kind:** functional
- **status:** active

### jido.agent_server2.I32 — Safe error Signals

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Dispatch only the terminal summary to the configured Signal destination with trace and causation. Do not emit another error Signal for an incoming jido.agent_server2.error Signal. Dispatch failure stops the activation safely.
- **why:** Error reporting must not disclose raw values or create emission loops.
- **kind:** functional
- **status:** active

### jido.agent_server2.I33 — Runtime observation

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Emit safe lifecycle start/stop, turn start/stop/settled, commit, and returned-directive events. Carry trace context through lifecycle tasks, Action context, and native Task Logger metadata. Label the server process. Reject caller-supplied trace_context.
- **why:** Runtime observation must follow ownership without disclosing input or state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I34 — Bounded opt-in history

- **scope:** `Jido.AgentServer2.history/1`
- **must:** Return no history by default. When debug is enabled, retain at most debug_max_events terminal summaries, in completion order, dropping the oldest. Keep last_outcome available without history.
- **why:** Debug work must have a fixed retention bound and exclude raw values.
- **kind:** functional
- **status:** active

### jido.agent_server2.I35 — Stable supervision identity

- **scope:** `Jido.AgentServer2.child_spec/1`
- **must:** Use the instance, partition, and Agent id as a stable child identity. Restart after abnormal exit with the same Agent id. Use transient restart so explicit stop does not restart.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I36 — Instance ownership and lookup

- **scope:** `Jido.AgentServer2.start/1`
- **must:** Start under the selected instance supervisor with its shared Runner and Registry. Claim one owner per instance, partition, and Agent id. Jido lookup must find the ready server. Reject cross-instance Runners and partitions without an instance. Stop on lost instance, Registry, or ownership guard.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I37 — OTP names and liveness

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Support local, global, and via names and live local AgentServer2 checks. Instance registration remains separate from an explicit OTP name. Do not identify an unrelated process as AgentServer2.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I38 — Instance runtime defaults

- **scope:** `Jido.AgentServer2.start/1`
- **must:** Read validated agent_server2 instance defaults at startup. Explicit server options override instance settings; instance turn_timeout overrides application and built-in defaults. A live server keeps its resolved settings.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I39 — Complete directive admission

- **scope:** `Jido.AgentServer2.call/3`
- **must:** Reject an unsupported directive, invalid outbound Signal or dispatch target, or batch above max_directives_per_turn before commit or any effect. Emit can use an explicit destination, a validated default, or self cast. Custom directives require a handler.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I40 — Ordered post-commit effects

- **scope:** `Jido.AgentServer2.call/3`
- **must:** Run each accepted directive once in batch order after committing the candidate once. Hold queued turns until the batch ends. A later turn uses the committed state.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I41 — Commit reply boundary

- **scope:** `Jido.AgentServer2.call/3`
- **must:** Send commit success before starting directive work. Keep committed reads, status, and progress available during effects. Cancellation after commit returns not_running and cannot undo commit.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I42 — Effect failure isolation

- **scope:** `Jido.AgentServer2.status/1`
- **must:** Stop the batch on a returned error, callback exception, or invalid handler result. Keep the committed Agent, revision, success reply, and terminal turn outcome. Record a safe last_effect_outcome and allow later work after confirmed effect task completion.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I43 — Effect deadline

- **scope:** `Jido.AgentServer2.start_link/1`
- **must:** Use a separate finite directive_timeout, default 5000 ms, for the entire batch. Recheck the clock before accepting results or starting the next effect. Stop the task before releasing queued turns. Ignore stale effect timeout messages.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I44 — Effect ownership

- **scope:** `Jido.AgentServer2.stop/3`
- **must:** Run directive work in owned linked tasks with propagated trace context and reject direct or nested owned turn requests. Stop effects after explicit server stop or owner death. Stop the activation after effect lifecycle ownership loss without changing the committed turn outcome. Handler child work must stay linked while the handler runs and finish before it returns; linking alone does not retain ownership after callback return.
- **why:** Keep runtime ownership and the commit boundary explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I45 — Signal destination resolution

- **scope:** `Jido.AgentServer2`
- **must:** Use explicit Emit dispatch before default_dispatch, then self cast. Inherit the instance for unscoped Bus targets and keep explicit scopes. Propagate trace and causation.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I46 — Submission is not delivery

- **scope:** `Jido.AgentServer2`
- **must:** Self-emission runs after commit and obeys normal turn admission. Cast acceptance does not promise execution, commit, or confirmed delivery.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I47 — Terminal Stop directive

- **scope:** `Jido.AgentServer2`
- **must:** Reject a Stop that is not last before any commit or effect. A valid Stop follows the success reply and preserves a clean shutdown reason.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I48 — Reported post-commit errors

- **scope:** `Jido.AgentServer2`
- **must:** Apply the failure policy to reported errors after commit, stop the batch, and preserve the saved successful turn, revision, and caller reply. Provide a committed directive-failure summary without raw errors in status.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I49 — Supervised application processes

- **scope:** `Jido.AgentServer2`
- **must:** Require a Jido instance and a valid OTP child specification before committing SpawnProcess. Start the application process under that instance supervisor; do not claim AgentServer ownership of its lifetime.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I50 — Plugin tree ownership

- **scope:** `Jido.AgentServer2`
- **must:** Own all provisional and ready Plugin runtime trees outside Agent state. Use normal OTP supervision for provisional and ready roots. Start functions must return within a bounded time; long work belongs in readiness. A readiness timeout closes admission immediately; supervisor cleanup settles an already-running bounded start before shutdown finishes. Confirm resource death before explicit stop returns, including finite shutdown of roots that trap exits. Preserve external shared resources. Recover required root loss through the activation strategy and refresh references before accepting turns.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I51 — Plugin readiness boundary

- **scope:** `Jido.AgentServer2`
- **must:** Start all roots before ordered readiness checks. Keep reads available during initialization, reject turns with not_ready, and publish instance lookup only after readiness. await_ready caller timeout must not cancel startup.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I52 — Separate readiness deadline

- **scope:** `Jido.AgentServer2`
- **must:** Validate a finite readiness_timeout with a 5000 ms default. Bound admission during startup and readiness; cleanup of an already-running supervisor start waits for its bounded callback to settle. Reject a late readiness result even before timer delivery; stop provisional resources on expiry.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I53 — Ordered live Plugin admission

- **scope:** `Jido.AgentServer2`
- **must:** Run declared live admission after pure preparation and in declaration order. Permit rejection or one package-owned transient runtime input. Support Plugins without runtime roots. Rejection, invalid results, and exceptions must not execute or commit.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I54 — Admission isolation and control

- **scope:** `Jido.AgentServer2`
- **must:** Preserve prepared input, caller context, Signal, Agent, and Plugin state ownership during live admission. Keep reads, timeout, cancellation, and reentrant request rejection effective while admission callbacks run.
- **why:** Preserve the startup, commit, and resource ownership boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server2.I55 — Ordered commit notifications

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Run selected after_commit callbacks in declaration order for every successful commit, including turns without directives. Supply the exact committed owned state, identity, turn ID, and revision. Reply before callbacks and hold queued turns until callbacks and effects finish.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I56 — Commit hook failure isolation

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Stop later hooks and directives on a returned error, exception, or invalid result. Preserve committed state, revision, and the successful turn outcome.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I57 — Separate commit hook budget

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Use a separate finite commit_timeout, default 5000 ms, for the whole notification batch. Accept instance defaults and explicit overrides. Confirm callback termination before queued work. Reject invalid budgets and check the deadline before accepting results.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I58 — Plugin directive ownership and context

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Validate the complete batch before commit. Dispatch declared runtime Plugin directives through their owner before any fallback handler, in order after all commit hooks. Supply only committed owned state, revision, source and effective Signals, transient caller context, and identity.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I59 — Plugin directive failure isolation

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Stop later effects on Plugin dispatch errors, exceptions, invalid results, or timeout. Terminate owned callback work and preserve committed state and the successful turn outcome.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I60 — Pre-commit rejection has no callbacks

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Do not notify Plugins or execute directives for failed turns or rejected batches. Preserve the previous state and revision.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I61 — Owned post-commit callbacks

- **scope:** `Jido.AgentServer2.call/3`, `Jido.AgentServer2.status/1`
- **must:** Keep inspection available during callbacks. Stop owned hook and directive tasks on server shutdown or death. Reject synchronous turn requests from owned callbacks to prevent deadlock. Callback child work must stay linked while the callback runs and finish before it returns. Plugin runtime trees own resources that must remain after callback return.
- **why:** Keep the commit and runtime ownership boundaries explicit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I62 — OTP Plugin startup results

- **scope:** `Jido.AgentServer2.start_link/1`, `Jido.AgentServer2.Activation`
- **must:** Accept both {:ok, pid} and {:ok, pid, info} from a valid Plugin child start. Track the same root PID, use it for readiness and runtime callbacks, and retain the same cleanup guarantees for both success forms.
- **why:** Valid OTP child starts must not fail because they return additional startup information.
- **kind:** functional
- **status:** active

### jido.agent_server2.I63 — Activation and worker identity

- **scope:** `Jido.AgentServer2`
- **must:** Supervise one request worker under one activation root, including Agents without runtime Plugins. child_spec must return the actual supervisor root with correct type. Activation.start_link returns `{:ok, root}`. Instance start, child spawn, and lookup return the worker. Explicit stop waits for the complete activation to die. Keep bare start_link worker startup separate and reject runtime Plugins and persistence there.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I64 — Recovery generations

- **scope:** `Jido.AgentServer2`
- **must:** Recover the server and required Plugin roots together with one_for_all. Use fresh worker references, generation, ordered readiness, and the activation's last published Agent and revision. Close the previous turn's Runic scope before admitting another turn, including when the old Worker has already stopped. Stop recovery if cleanup exceeds the readiness budget. Required Plugin roots must belong to this activation; reject external named roots and ignored starts. Ignore stale results and deadlines. Permit Plugin supervisors to recover internal leaves without replacing the Agent. Activation replacement uses original startup values until durable restore is implemented.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I65 — Owned child activations

- **scope:** `Jido.AgentServer2`
- **must:** Start tagged owned children under a lazy DynamicSupervisor in the parent activation. Inspect current worker and root separately after recovery. Stop complete child trees on explicit child stop or parent activation shutdown. Keep nested children and Plugins owned.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I66 — Independent child lifetime

- **scope:** `Jido.AgentServer2`
- **must:** Place independent children under the Jido instance. Observe parent activation loss separately from worker recovery. Support stop, continue, and emit_orphan policies with the jido.agent_server2.orphaned Signal. Continuing children retain Plugins and can execute after parent shutdown. Keep all relationship metadata outside Agent state.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I67 — Adoption

- **scope:** `Jido.AgentServer2`
- **must:** Adopt an independent orphan in the same instance and partition. Reject attached children, self-adoption, cycles, cross-instance adoption, bare workers, unavailable ancestry, and pending orphan dispatch. Rejection must preserve the child and release reservations. Preserve the new relationship through worker recovery. Emit the configured orphan Signal under a finite owned dispatch budget. Permit adoption after dispatch completes. Release a lost adopted-child tag after whole activation replacement; do not restore that adoption.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I68 — Child startup isolation

- **scope:** `Jido.AgentServer2`
- **must:** Validate child instances, tags, placement, and parent policy before creating resources. Reject owned survival policies, duplicate live tags, and missing instance or orphan dispatch. Independent placement without an instance returns `{:error, :jido_instance_required}`. Roll back failed startup reservations and monitors. If instance start or child spawn cannot resolve a live worker, stop the new root and return `{:error, :worker_unavailable}`. A dead startup caller must not attach an old child after its tag is reused. Reuse tags after confirmed shutdown. Keep restart references current and remove terminal child records.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I69 — Incumbent coexistence

- **scope:** `Jido.AgentServer2`
- **must:** Host existing AgentServer workers and AgentServer2 activation roots in one instance without changing the existing implementation. Preserve shared identity uniqueness and lookup, and keep the two execution APIs operational.
- **why:** Keep process ownership, client identity, and domain state separate.
- **kind:** functional
- **status:** active

### jido.agent_server2.I70 — Stable Ref identity

- **scope:** `Jido.AgentServer2`
- **must:** Resolve exact namespace, partition, and Agent ID through the existing Ref facade. Keep process and storage metadata out of the Ref. Reject invalid or mismatched identity. Report not_found when no worker is registered, recovering for a registered starting AgentServer2, and unavailable when the local Registry or resolved worker is lost. Resolve each operation again after worker recovery without automatic turn replay.
- **why:** Client identity must survive worker replacement without retaining a stale PID.
- **kind:** functional
- **status:** active

### jido.agent_server2.I71 — Ref operation routing

- **scope:** `Jido.AgentServer2`
- **must:** Route Ref call, cast, submit, committed reads, status, and stop to AgentServer2 with their existing result and caller-wait contracts. Support generated instance submit, await, and abandon wrappers. Preserve incumbent Ref operations and results. Reject unsupported runtime operations explicitly instead of sending an incompatible request. Use the standard wait validation for committed reads, status, Plugin state, and children. Keep caller timeout separate from execution cancellation.
- **why:** Both runtimes share identity infrastructure but have different request protocols.
- **kind:** functional
- **status:** active

### jido.agent_server2.I72 — Local checkpoint publication

- **scope:** `Jido.AgentServer2`, `Jido.AgentServer2.Activation`
- **must:** Seed the activation checkpoint with its complete initial Agent and revision zero. Atomically publish the complete validated candidate and next revision before installing committed state or replying success. Successful unchanged state also advances the revision once. Failed, invalid, timed-out, and cancelled turns must not change the checkpoint.
- **why:** Recovery must select one complete committed value.
- **kind:** functional
- **status:** active

### jido.agent_server2.I73 — Checkpoint recovery validation

- **scope:** `Jido.AgentServer2.Activation`
- **must:** In memory-only mode, restore the last published Agent and revision before constructing Plugin Init or opening admission. Validate complete state, nonnegative revision, Agent identity, and exact startup definition including its version. Stop recovery after a missing, corrupt, or incompatible local checkpoint; never substitute fresh state. Recreate Plugin resources and readiness from the restored value.
- **why:** Restart must not erase commits or initialize resources from stale domain data.
- **kind:** functional
- **status:** active

### jido.agent_server2.I74 — Commit crash windows

- **scope:** `Jido.AgentServer2`
- **must:** In memory-only mode, a crash before checkpoint publication restores the previous committed value. A crash after publication restores the new value even if the caller has not collected success. Do not replay the accepted turn, post-commit hooks, or directives. Retain the previous execution cleanup barrier and serial admission during recovery.
- **why:** A lost reply can leave the caller uncertain about commit; it must not trigger implicit execution replay.
- **kind:** functional
- **status:** active

### jido.agent_server2.I75 — Local checkpoint lifetime

- **scope:** `Jido.AgentServer2.Activation`
- **must:** Store only the canonical Agent and commit revision as the local checkpoint. Preserve existing local Agent-state rules, including schema-permitted local values, without portable serialization or checkpoint callbacks. Keep transient context and runtime records outside it. Delete it with the activation; memory-only activation replacement starts from original arguments. Opt-in durable restore follows I79 and I81. Bare-worker startup has no activation checkpoint. Child relationship restoration remains separate.
- **why:** Local state recovery must not become an accidental durable or portable-data contract.
- **kind:** functional
- **status:** active

### jido.agent_server2.I76 — Checkpoint publication failure

- **scope:** `Jido.AgentServer2.Activation`, `Jido.AgentServer2`
- **must:** Publish only against the expected preceding revision. Reject a conflict or unavailable checkpoint. Do not report commit success or run post-commit work after publication failure. End the activation with controlled execution cleanup.
- **why:** The worker must not continue with a commit that recovery cannot reproduce.
- **kind:** functional
- **status:** active

### jido.agent_server2.I77 — Required durable commit boundary

- **scope:** `Jido.AgentServer2`
- **must:** Create revision zero before readiness. Save each successful complete candidate outside the server with the current expected revision and next revision. Hold new turns and keep reads available. Publish the local checkpoint, success, hooks, and directives only after a confirmed write. Give save its own finite deadline. Caller wait timeout and turn cancellation do not cancel an accepted save; cancellation returns commit_in_progress.
- **why:** Success must have a confirmed durable commit.
- **kind:** functional
- **status:** active

### jido.agent_server2.I78 — Failed or uncertain required write

- **scope:** `Jido.AgentServer2`
- **must:** On conflict, rejected write, adapter fault, invalid result, or uncertain write, return no commit success and end the activation through controlled cleanup. Save deadline expiry is indeterminate. Confirm owned storage task and execution cleanup. Do not run post-commit callbacks or silently continue without persistence.
- **why:** An uncertain writer must not accept more work.
- **kind:** functional
- **status:** active

### jido.agent_server2.I79 — Explicit durable restore

- **scope:** `Jido.AgentServer2`
- **must:** Select create or restore explicitly. Create must not replace an existing record. Restore must fail on missing, deleted, corrupt, incompatible, or unavailable data. Bound load outside the server. Validate the complete Agent, identity, exact definition/version, and nonnegative revision before Plugin startup or readiness. Use the existing persistence record and checkpoint APIs; do not add implicit migration or fresh-state fallback.
- **why:** Restore must preserve the saved domain state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I80 — Plugin reconstruction from saved state

- **scope:** `Jido.AgentServer2`
- **must:** Restore Plugin-owned domain state through existing checkpoint conversion contracts before constructing Plugin Init. Supply the saved state and revision to newly created resources. Use the versioned definition's Plugin declarations/options and existing readiness callbacks. Do not save runtime trees or handles and do not replay commit hooks or directives.
- **why:** Resources are rebuilt from domain state.
- **kind:** functional
- **status:** active

### jido.agent_server2.I81 — Durable authority after worker loss

- **scope:** `Jido.AgentServer2`, `Jido.AgentServer2.Activation`
- **must:** Every persistent worker replacement loads durable storage before admission. A write accepted before worker death can be restored even if the local checkpoint and reply were not published. Replace the activation checkpoint with the validated durable revision. Do not replay the interrupted turn.
- **why:** Durable storage can be ahead of the local checkpoint.
- **kind:** functional
- **status:** active

### jido.agent_server2.I82 — Portable save boundary

- **scope:** `Jido.AgentServer2`
- **must:** Preserve local schema-permitted state. At durable create and commit, apply existing Agent and Plugin checkpoint conversions and require a portable stored record. Unsupported state must fail the required write without publishing success.
- **why:** Runtime handles must not enter saved records.
- **kind:** functional
- **status:** active

### jido.agent_server2.I83 — Durable runtime configuration

- **scope:** `Jido.AgentServer2`
- **must:** Keep persistence disabled by default. Accept an explicit adapter or inherit the instance adapter. Require an activation and a Jido instance with a stable namespace. Validate the finite persistence_timeout and create/restore policy. Preserve the public authoring DSL and ordinary memory-only workers.
- **why:** Durability must have an explicit runtime boundary.
- **kind:** functional
- **status:** active

### jido.agent_server2.I84 — Closed admission

- **scope:** `Jido.AgentServer2`
- **must:** Close admission atomically for quiesce or hibernate. Reject new and OTP-postponed turns with quiesced, drain queued requests before completion, and never replay them on resume. Keep Agent and status reads available.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I85 — Quiescent boundary

- **scope:** `Jido.AgentServer2`
- **must:** Finish active work by default. With active: cancel, cancel only pre-commit work and confirm execution cleanup. Accepted required writes, failure policy, commit hooks, directives, and orphan delivery must settle before quiescence. Resume only after that boundary.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I86 — Bounded control

- **scope:** `Jido.AgentServer2`
- **must:** Use a finite control deadline and a finite caller wait when the server cannot respond. Reject concurrent controls. A quiesce deadline returns an explicit failure and leaves admission closed until work settles and an explicit resume succeeds. Ignore stale control and idle timers.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I87 — Control callback safety

- **scope:** `Jido.AgentServer2`
- **must:** Reject synchronous quiesce, resume, hibernate, and stop requests from owned turn, bootstrap, storage, or orphan callback work that would deadlock. Keep nonblocking reads available.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I88 — Control recovery

- **scope:** `Jido.AgentServer2`
- **must:** Keep closed or blocked admission and attached-owner identities in activation-owned runtime metadata across worker replacement. Rebuild monitors before readiness. Do not reopen admission or replay interrupted controls during recovery. Keep these records out of Agent checkpoints.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I89 — Attached owners

- **scope:** `Jido.AgentServer2`
- **must:** Attach and detach are idempotent per PID. Monitor each attached owner once. Match its monitor reference without consuming other lifecycle DOWN events for the same PID. An attached owner prevents idle expiry. Last detach or owner DOWN starts a new idle budget only when the Agent is idle and admission is open.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I90 — Idle deadline

- **scope:** `Jido.AgentServer2`
- **must:** Disable idle expiry by default. Accept a finite idle_timeout from instance defaults or startup override. Touch and accepted work restart the idle budget. Do not stop active work or post-commit effects, and ignore stale timer tokens. Reads do not count as activity.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I91 — Confirmed hibernation

- **scope:** `Jido.AgentServer2`
- **must:** Require configured persistence and an activation. Quiesce before saving the current Agent and revision in owned bounded work through the existing persistence API. Keep reads available. Return success only after save confirmation and activation DOWN. Do not replay effects or change the revision for this save.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I92 — Failed hibernation

- **scope:** `Jido.AgentServer2`
- **must:** On save failure retain the live Agent and return reason plus resumable?. A known no-write failure restores prior admission. Conflict or uncertain write, task loss, or save deadline keeps admission blocked, including across worker recovery. Resume must reject blocked admission. Required commit failure retains its fail-stop contract.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I93 — Explicit idle policy

- **scope:** `Jido.AgentServer2`
- **must:** Use idle_policy: stop by default, without a save. Require persistence for idle_policy: hibernate and use the same save-and-stop boundary. A failed automatic save keeps admission closed and does not create a retry loop.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server2.I94 — Control configuration

- **scope:** `Jido.AgentServer2`
- **must:** Validate control options, finite control deadlines, owner PIDs, idle timeout, and idle policy before dependent work. Keep runtime changes in one file, preserve public authoring DSL, and leave AgentServer intact.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active
