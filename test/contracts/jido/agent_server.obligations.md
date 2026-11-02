---
modules:
  - Jido.AgentServer.Core
---

## Purpose

Protect the core `Jido.AgentServer` request, Turn, failure-policy, and runtime
control behavior. Other AgentServer components own activation, effects, Plugin
runtime, composition, durable state, and durable Flow progress.

`Jido.AgentServer` is the single public runtime facade. This component owns the
facade boundary and its core operations. Focused AgentServer components own the
behavior of delegated facade operations. AgentServer has no separate DSL. Jido
instance options and direct function options are its authoring surface.

## Obligations

**Startup, requests, and turn lifecycle**

### jido.agent_server.I1 — Startup validation

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Start only with a complete Agent instance and a live named Runner with the temporary Store, including the shared instance Store. Reject invalid options, definitions, and unrelated or stale Runner names. Enforce instance Runner ownership.
- **why:** Invalid startup must not create an activation.
- **kind:** functional
- **status:** active

### jido.agent_server.I2 — Runtime defaults

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Use a 60000 ms built-in turn timeout and the declared built-in runtime defaults. Read valid application turn_timeout defaults at startup; do not accept other application runtime defaults. Explicit values override unused application configuration. Require unique startup, instance-default, and application-configuration keys. Reject unknown configuration keys and finite caller waits outside 0..4294967295. Accept non-negative integer Turn timeouts, including 90 days; arm bounded timer intervals without resetting the active or saved deadline. Name each invalid timeout field in its validation error.
- **why:** Configuration errors must be detected before work starts.
- **kind:** functional
- **status:** active

### jido.agent_server.I3 — Signal validation

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.cast/3`
- **must:** Reject malformed Signals before execution. Preserve the committed Agent and revision and keep the activation alive.
- **why:** Bad input must not destroy live state.
- **kind:** functional
- **status:** active

### jido.agent_server.I4 — Transient context

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.cast/3`
- **must:** Pass supported map, keyword, or nil context to the turn. Reject duplicate or unknown options and reserved keys. Keep transient values out of Agent state and Signal data.
- **why:** Runtime input must not become domain state.
- **kind:** functional
- **status:** active

### jido.agent_server.I5 — Responsive committed reads

- **scope:** `Jido.AgentServer.agent/1`, `Jido.AgentServer.status/1`
- **must:** Return committed state and a bounded status while a turn or cleanup is active. Report Agent identity, active turn and Signal IDs, starting revision, stage, and queue counts. Report handoff_pending while a released successor owns the next Turn. Separate reads are not atomic.
- **why:** Inspection must remain available without exposing input or internal request handles.
- **kind:** functional
- **status:** active

### jido.agent_server.I6 — Serial execution

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.cast/3`
- **must:** Run at most one turn per activation. Queued work starts from the previous committed result.
- **why:** Turns must not overwrite each other.
- **kind:** functional
- **status:** active

### jido.agent_server.I7 — One commit

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.status/1`
- **must:** Commit the complete validated candidate once on success and increment the runtime revision once, including successful unchanged state.
- **why:** Completion must have one commit boundary.
- **kind:** functional
- **status:** active

### jido.agent_server.I8 — Failure isolation

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`
- **must:** Action or Flow failure, routing failure, or invalid candidate preserves the complete committed Agent and revision. Ordinary failure permits later work under the default policy.
- **why:** Rejected work must not corrupt state.
- **kind:** functional
- **status:** active

### jido.agent_server.I9 — Public API boundary

- **scope:** documented `Jido.AgentServer` functions and types
- **must:** Keep one exact documented facade for lifecycle, requests, control, observation, Plugin state, composition, and durability. Keep the owner-bound pending handle opaque. Keep `Core`, `Pending`, `Store`, state-machine callbacks, and owner implementation modules internal. Do not add a second AgentServer DSL or expose coordinator internals.
- **why:** Users need one stable runtime entry point while focused components retain behavior ownership.
- **kind:** functional
- **status:** active

### jido.agent_server.I10 — Pending replies

- **scope:** `Jido.AgentServer.submit/3`, `Jido.AgentServer.await/2`
- **must:** Return a temporary handle without waiting for turn completion. Only the submitting process can collect it. Wait timeout returns an error and permits a later wait without cancelling work.
- **why:** Asynchronous requests need explicit reply ownership.
- **kind:** functional
- **status:** active

### jido.agent_server.I11 — Caller wait

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.cancel/2`
- **must:** Caller wait timeout exits as an OTP call does. It does not cancel accepted turn work or revoke accepted cancellation.
- **why:** Waiting and execution have separate limits.
- **kind:** functional
- **status:** active

### jido.agent_server.I12 — Reply disposal

- **scope:** `Jido.AgentServer.abandon/1`
- **must:** Only the submitting process can discard a pending reply. Remove its monitor, discard a queued turn result and buffered Reply Signals, and prevent late turn results and Reply Signals without cancelling the turn.
- **why:** Unwanted replies must not retain Agent values in the caller mailbox.
- **kind:** functional
- **status:** active

### jido.agent_server.I13 — Casts

- **scope:** `Jido.AgentServer.cast/3`
- **must:** Accept a valid cast without a result handle. Apply the same turn validation and commit rules. Dropped or failed casts do not change committed state.
- **why:** Best-effort requests still require state safety.
- **kind:** functional
- **status:** active

### jido.agent_server.I14 — Queue capacity

- **scope:** `Jido.AgentServer.start_link/1`, `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.cast/3`
- **must:** Bound postponed turns separately from the active turn and mailbox. Reject excess requests with limit and count; drop excess casts. Support zero and infinity.
- **why:** Admission must have a clear capacity limit.
- **kind:** functional
- **status:** active

### jido.agent_server.I15 — Admission expiry

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`
- **must:** Reject expired requests before execution, including replay of queued work. Zero always expires. An admission deadline does not stop a turn that already started.
- **why:** Queued work must retain its own admission budget.
- **kind:** functional
- **status:** active

### jido.agent_server.I16 — Owned requests

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`, `Jido.AgentServer.cancel/2`, `Jido.AgentServer.cancel_turn/3`
- **must:** Reject direct and nested OTP Task requests from detected owned work with reentrant_turn, including execution startup. Allow unrelated callers even if an Action monitors them. Reads remain available. Detection follows local caller ancestry to depth eight, not arbitrary process protocols.
- **why:** A turn must not wait for itself or cancel its own execution.
- **kind:** functional
- **status:** active

### jido.agent_server.I17 — Whole-turn deadline

- **scope:** `Jido.AgentServer.start_link/1`, `Jido.AgentServer.await/2`
- **must:** Apply the active timeout to preparation, startup, execution, candidate validation, and cleanup. Recheck before commit. Zero cannot commit; infinity disables the active deadline. Reply with turn_timeout only after cleanup.
- **why:** A delayed timer must not permit a late commit.
- **kind:** functional
- **status:** active

### jido.agent_server.I18 — Cancellation

- **scope:** `Jido.AgentServer.cancel/2`
- **must:** Stop active owned work, preserve committed state and revision, and return ok only after cleanup. The turn receives cancelled. Idle cancellation and cancellation after commit during effects or after terminal cleanup during failure policy return not_running. A Handoff chain is the narrow exception: after its predecessor commits, cancellation owns the chain until the successor settles and must prevent a not-yet-started successor. Repeated cancellation shares cleanup; the first abort reason wins.
- **why:** Cancellation must have a confirmed ownership boundary.
- **kind:** functional
- **status:** active

### jido.agent_server.I19 — Targeted cancellation

- **scope:** `Jido.AgentServer.cancel_turn/3`
- **must:** Cancel only the matching active turn ID. Reject a stale ID without affecting current work. Keep one active ID through the turn.
- **why:** An old request must not cancel newer work.
- **kind:** functional
- **status:** active

### jido.agent_server.I20 — Successful cleanup

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`
- **must:** Confirm Worker and execution Task cleanup before success and before the next turn. Do not retain execution records in the temporary Store, including the shared instance Store.
- **why:** Successful turns must not accumulate execution resources.
- **kind:** functional
- **status:** active

### jido.agent_server.I21 — Abort cleanup

- **scope:** `Jido.AgentServer.cancel/2`, `Jido.AgentServer.cancel_turn/3`
- **must:** Confirm cleanup after timeout or cancellation at preparation, Worker startup, execution, and validation. Fence in-flight Worker startup before admitting later work. Keep reads available during cleanup.
- **why:** An aborted startup must not leave detached execution.
- **kind:** functional
- **status:** active

### jido.agent_server.I22 — Server ownership

- **scope:** `Jido.AgentServer.stop/3`
- **must:** Stop owned Worker and Action work after explicit stop or abrupt server death. Preserve standard clean shutdown reasons.
- **why:** Execution must not outlive its owner.
- **kind:** functional
- **status:** active

### jido.agent_server.I23 — Lifecycle loss

- **scope:** `Jido.AgentServer.await/2`
- **must:** Stop the activation when its Runner, Worker, or lifecycle Task is lost, or cleanup cannot be confirmed. Do not commit a candidate or start queued work after ownership becomes uncertain.
- **why:** Unknown execution ownership cannot be treated as safe completion.
- **kind:** functional
- **status:** active

### jido.agent_server.I24 — Late messages

- **scope:** `Jido.AgentServer.status/1`, `Jido.AgentServer.cancel_turn/3`
- **must:** Ignore stale completion and timeout messages. A discarded result cannot commit or affect a later turn.
- **why:** Mailbox races must not cross turn boundaries.
- **kind:** functional
- **status:** active

### jido.agent_server.I25 — Safe failure logs

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.cast/3`
- **must:** Return Action or Flow errors to the caller without raw Runner failure warnings containing node input or error values. Failed casts retain an Agent and turn ID summary. This does not filter logs written by application code.
- **why:** Runtime failure reporting must not expose private input.
- **kind:** functional
- **status:** active

**Execution policy and observation**

### jido.agent_server.I26 — Policy validation

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Reject duplicate or unknown execution and hook keys, invalid timeouts, attempts, backoff, concurrency, hook arities, error policies, unbounded policy waits, and invalid history limits before startup.
- **why:** Runtime policy must be valid before execution starts.
- **kind:** functional
- **status:** active

### jido.agent_server.I27 — Eligible bounded retries

- **scope:** `Jido.AgentServer.call/3`
- **must:** Use the owned Runner for per-node timeouts and retries. Run at most max_attempts attempts, retry only retryable Action errors, apply configured backoff, and let the outer deadline or cancellation stop retry work.
- **why:** Retries must not bypass ownership, error classification, or the commit boundary.
- **kind:** functional
- **status:** active

### jido.agent_server.I28 — Execution scheduling and hooks

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Apply max_concurrency to Flow nodes within one serial turn. Compose supported Worker hooks with ownership, trace propagation, and safe runtime failure logging.
- **why:** Execution policy must not change turn isolation.
- **kind:** functional
- **status:** active

### jido.agent_server.I29 — One terminal summary

- **scope:** `Jido.AgentServer.status/1`
- **must:** Record one terminal summary for each admitted turn: succeeded, failed, cancelled, timed_out, or indeterminate. Report stage, commit indicator, versions, IDs, directive count, and duration without raw state, input, or errors. Emit one settled event when the process can run its terminal callback; an untrappable kill cannot emit it.
- **why:** Observers need one safe statement of the commit result.
- **kind:** functional
- **status:** active

### jido.agent_server.I30 — Failure decisions

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Default to continuing after ordinary failure. Support stop_on_error and a consecutive max_errors threshold; success resets the count. Stop decisions preserve the original error reply.
- **why:** Failure policy must not alter committed domain state.
- **kind:** functional
- **status:** active

### jido.agent_server.I31 — Bounded custom failure policy

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Run custom error callbacks outside the server with a finite policy deadline after terminal cleanup. Keep reads available and reject owned reentrant turns. Serialize queued work until the decision. Stop safely on timeout, exception, invalid return, or callback failure and preserve the original turn error.
- **why:** Policy work must not block reads or revise a terminal outcome.
- **kind:** functional
- **status:** active

### jido.agent_server.I33 — Runtime observation

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Emit safe lifecycle start/stop, turn start/stop/settled, commit, and returned-directive events. Carry trace context through lifecycle tasks, Action context, and native Task Logger metadata. Label the server process. Reject caller-supplied trace_context.
- **why:** Runtime observation must follow ownership without disclosing input or state.
- **kind:** functional
- **status:** active

### jido.agent_server.I34 — Bounded opt-in history

- **scope:** `Jido.AgentServer.history/1`
- **must:** Return no history by default. When debug is enabled, retain at most debug_max_events terminal summaries, in completion order, dropping the oldest. Keep last_outcome available without history.
- **why:** Debug work must have a fixed retention bound and exclude raw values.
- **kind:** functional
- **status:** active

**Runtime control**

### jido.agent_server.I84 — Closed admission

- **scope:** `Jido.AgentServer`
- **must:** Close admission atomically for quiesce or hibernate. Reject new and OTP-postponed turns with quiesced, drain queued requests before completion, and never replay them on resume. Keep Agent and status reads available.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active
### jido.agent_server.I85 — Quiescent boundary

- **scope:** `Jido.AgentServer`
- **must:** Finish active work by default. With active: cancel, cancel only pre-commit work and confirm execution cleanup. Accepted required writes, failure policy, commit hooks, directives, and orphan delivery must settle before quiescence. Resume only after that boundary.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server.I86 — Bounded control

- **scope:** `Jido.AgentServer`
- **must:** Use a finite control deadline and a finite caller wait when the server cannot respond. Reject concurrent controls. A quiesce deadline returns an explicit failure and leaves admission closed until work settles and an explicit resume succeeds. Ignore stale control and idle timers.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server.I87 — Control callback safety

- **scope:** `Jido.AgentServer`
- **must:** Reject synchronous quiesce, resume, hibernate, and stop requests from owned turn, bootstrap, storage, or orphan callback work that would deadlock. Keep nonblocking reads available.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active

### jido.agent_server.I94 — Control configuration

- **scope:** `Jido.AgentServer`
- **must:** Validate unique control option keys, finite control deadlines, owner PIDs, idle timeout, and idle policy before dependent work. Keep runtime changes in one file, preserve the direct option surface, and keep unrelated runtime APIs unchanged.
- **why:** Control must preserve Agent state, ownership, and bounded process lifetime.
- **kind:** functional
- **status:** active
