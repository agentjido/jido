---
modules:
  - Jido.AgentServer.Plugin
  - Jido.AgentServer.Plugin.Callbacks
---

## Purpose

Protect generic live Plugin hosting inside one AgentServer activation. The
component owns runtime roots and Plugin callbacks. It does not own Plugin
authoring, bundled Plugin behavior, Agent evaluation, state-machine phases, or
general effect execution.

## Obligations

### jido.agent_server.plugin_runtime.I1 — Runtime root ownership and reconstruction

- **scope:** `Jido.AgentServer.Plugin`, AgentServer startup and recovery
- **must:** Start each declared runtime root under the activation with its committed owned state and revision. Accept valid OTP `{:ok, pid}` and `{:ok, pid, info}` starts, track the root PID, and support a supervised root tree. Confirm owned root death during stop, startup failure, timeout, owner loss, or required group recovery. Preserve external shared resources. A bare worker cannot host runtime roots.
- **why:** Plugin process state must have one OTP owner and must be rebuilt from committed Agent state.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I2 — Ordered readiness boundary

- **scope:** `Jido.AgentServer.Plugin.bootstrap/2`, `Jido.AgentServer.await_ready/2`
- **must:** Start all declared roots before readiness checks. Check readiness in declaration order with the live root reference. Keep reads available, reject Turns as not ready, and publish instance lookup only after all checks pass. A caller wait timeout does not cancel startup. A readiness callback cannot wait for its own activation.
- **why:** Admission must not open while a required Plugin is not ready.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I3 — Finite readiness budget

- **scope:** AgentServer Plugin bootstrap
- **must:** Use one finite readiness timeout, with 5000 ms as the default, for root startup and ordered readiness. Reject invalid values before startup. Reject results at or after the deadline even before timer delivery. Close admission immediately on expiry and confirm provisional task and root cleanup, including bounded starts and roots that trap exits.
- **why:** Plugin startup must not leave an activation indefinitely unavailable or partly owned.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I4 — Ordered live admission

- **scope:** `Jido.AgentServer.Plugin.admit/2`
- **must:** Run declared admission callbacks after pure Plugin preparation and in declaration order. Supply the current root reference, prepared package input, committed owned state and revision, source Signal, caller context, and Agent identity. Accept one package-owned transient runtime input. Support a Plugin with no runtime root. A rejection, exception, or invalid result must prevent execution and commit.
- **why:** Live Plugin input must stay transient and must not bypass the commit boundary.
- **kind:** functional
- **status:** active

### jido.agent_server.plugin_runtime.I5 — Owned admission work

- **scope:** live Plugin admission callbacks
- **must:** Keep prepared input, caller context, Signal, Agent state, and each Plugin's owned state separate. Run admission as owned Turn work so reads, the Turn deadline, cancellation, cleanup, and reentrant request rejection remain effective.
- **why:** A live callback must not weaken Turn isolation or move transient values into Agent state.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I6 — Ordered commit notification

- **scope:** `Jido.AgentServer.Plugin.after_commit/3`
- **must:** Notify selected `after_commit` callbacks in declaration order after each successful commit, including commits with no Directives. Supply the exact committed owned state, Agent identity, Turn ID, revision, instance, and partition. Reply to the caller before callbacks, and hold later Turns until callbacks and effects finish. Use the current root reference.
- **why:** Plugins must observe only committed state and one ordered revision stream.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I7 — Commit callback failure and budget

- **scope:** post-commit Plugin callbacks
- **must:** Use one finite commit timeout, with 5000 ms as the default, for the complete commit-callback batch. Accept validated instance defaults and explicit overrides. Check the deadline before accepting results. On error, exception, invalid result, or timeout, stop later callbacks and effects, confirm callback cleanup, and keep the successful committed Agent, revision, and Turn result.
- **why:** A Plugin notification failure must not undo a commit or leave owned work active.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I8 — Outbound Signal preparation

- **scope:** `Jido.AgentServer.Plugin.Callbacks.prepare_dispatch/5`
- **must:** Run declared outbound preparation callbacks in reverse declaration order before effect delivery. Give each callback its current root reference, owned committed state, Signal context, and owner options. Validate the complete Signal after every transform and stop at the first explicit error, exception, or invalid result. A Plugin without this callback leaves the Signal unchanged.
- **why:** Live Plugin transforms must preserve one valid outbound Signal and must not expose another Plugin's owned state.
- **kind:** functional
- **status:** active

### jido.agent_server.plugin_runtime.I9 — Directive ownership and context

- **scope:** `Jido.AgentServer.Plugin.dispatch/3`
- **must:** Select the declared live Plugin owner before any fallback handler. Dispatch owned Directives in batch order after all commit callbacks. Supply only the current root reference, committed owned state and revision, source and effective Signals, transient Turn context, Agent identity, instance, and partition.
- **why:** A Plugin Directive needs one declared owner and a narrow committed context.
- **kind:** functional
- **status:** active

### jido.agent_server.plugin_runtime.I10 — Directive callback failure

- **scope:** live Plugin Directive dispatch
- **must:** Treat a returned error, exception, invalid result, or deadline expiry as an effect failure. Stop later effects, terminate owned callback work, and preserve the successful committed Agent, revision, and Turn result.
- **why:** External Plugin work must fail after, not through, the commit boundary.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I11 — Callback ownership boundary

- **scope:** live admission, commit, and Directive callbacks
- **must:** Do not run commit or Directive callbacks for a rejected batch or failed Turn. Keep inspection available while callbacks run. Reject synchronous Turn requests from owned callback work. Keep callback child work linked until the callback returns. Stop owned callback work on activation stop or callback timeout. Resources that must survive callback return belong in the supervised runtime root.
- **why:** Callback lifetime must be explicit and must not create detached work or a reentrant deadlock.
- **kind:** ordering
- **status:** active

### jido.agent_server.plugin_runtime.I12 — Safe live runtime replacement

- **scope:** live Plugin configuration changes
- **must:** Require existing autonomous roots that change to implement idempotent `quiesce/2` and `resume/2`. Quiesce affected roots before commit. Resume them after rejection, cancellation, or failed preparation. After commit, stop affected roots and rebuild them from the accepted owned state and revision before admission opens. Notify unchanged Plugins in declaration order and do not notify a replaced root for the replacement commit.
- **why:** Accepted Plugin data must be the authority for its live runtime without overlapping old and new generations.
- **kind:** ordering
- **status:** active
