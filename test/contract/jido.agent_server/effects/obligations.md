---
modules:
  - Jido.AgentServer.Directive
  - Jido.AgentServer.Directive.AgentSend
  - Jido.AgentServer.Directive.AgentStart
  - Jido.AgentServer.Directive.AgentStop
  - Jido.AgentServer.Directive.ErrorReport
  - Jido.AgentServer.Directive.OwnerSend
  - Jido.AgentServer.Directive.ProcessStart
  - Jido.AgentServer.Directive.ServerStop
  - Jido.AgentServer.Effects
  - Jido.Dispatch.Preparation
---

## Purpose

Protect the work that starts after one AgentServer Turn commits. This component
admits one complete Directive batch, confirms the commit to the caller, runs
the batch in order, and records a safe effect result.

This component does not own pure Agent evaluation, the commit itself, Plugin
root lifetime, child restart behavior, durable storage, or Signal transport.

The documented `Jido.AgentServer.Directive` constructors and their result
records are the public boundary. The effect engine and dispatch preparation
are internal. This component has no DSL.

## Obligations

### jido.agent_server.effects.I1 — Complete batch admission

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.Effects.validate_batch/2`
- **must:** Reject the complete batch before commit or effect work when a Directive is unsupported, an outbound Signal or dispatch target is invalid, or the batch is above the configured nonnegative limit. Accept the exact limit. A custom Directive needs an accepted owner or handler.
- **why:** A committed Turn must not contain effect work that the runtime cannot start.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I2 — Commit confirmation and ordered execution

- **scope:** `Jido.AgentServer.call/3`, `Jido.AgentServer.submit/3`
- **must:** Return the accepted Directive batch with commit success before effect work finishes. Run each Directive once in batch order after one commit. Keep later Turns queued until the batch ends, and start them from the committed Agent.
- **why:** Commit success and external work have different completion boundaries.
- **kind:** ordering
- **status:** active

### jido.agent_server.effects.I3 — Effect failure isolation

- **scope:** `Jido.AgentServer.status/1`
- **must:** Stop the remaining batch after a returned error, callback exception, or invalid handler result. Keep the committed Agent, revision, success reply, and terminal Turn result. Publish one safe effect result and start later queued work only after owned effect work stops.
- **why:** A failed effect must not undo or hide an accepted state change.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I4 — One finite batch deadline

- **scope:** `Jido.AgentServer.start_link/1`
- **must:** Use one finite directive timeout for the complete Directive batch, with 5000 ms as the default. Check the current clock before a result is accepted or the next effect starts. Stop active effect work before later Turns start. Ignore stale timeout messages.
- **why:** One batch must not hold the AgentServer without a bound.
- **kind:** ordering
- **status:** active

### jido.agent_server.effects.I5 — Owned effect work

- **scope:** `Jido.AgentServer.stop/3`, effect tasks
- **must:** Run effect work in linked tasks with the Turn trace. Reject direct and nested Turn requests from owned effect work. Stop active effect work when the server stops or its owner dies. Stop the activation when effect-task ownership is lost, without changing the committed Turn result.
- **why:** The server must know when post-commit work has fully stopped.
- **kind:** ordering
- **status:** active

### jido.agent_server.effects.I6 — Signal destination and context

- **scope:** `Jido.Agent.Directive.Emit`, `Jido.AgentServer.Effects`
- **must:** Use an explicit Emit destination before the configured default, then use self submission. Inherit the current Jido instance for an unscoped Bus target and keep an explicit scope. Propagate the Turn trace and source Signal causation.
- **why:** Outbound Signal routing must use one clear destination rule.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I7 — Submission is not delivery

- **scope:** self-directed `Jido.Agent.Directive.Emit`
- **must:** Submit a self-directed Signal only after commit and apply normal Turn admission. A cast acceptance does not confirm execution, commit, or delivery.
- **why:** Asynchronous submission is not a delivery receipt.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I8 — Terminal ServerStop

- **scope:** `Jido.AgentServer.Directive.ServerStop`
- **must:** Reject ServerStop before commit when it is not the last Directive. For a valid ServerStop, return commit success first and then stop with the requested clean reason.
- **why:** A terminal Directive cannot leave later accepted work in its batch.
- **kind:** ordering
- **status:** active

### jido.agent_server.effects.I9 — Safe post-commit error reporting

- **scope:** `Jido.AgentServer.Directive.ErrorReport`, `Jido.AgentServer.start_link/1`
- **must:** Stop the remaining batch and apply the failure policy after commit. Keep the successful Turn result and revision. Report only a committed effect-failure summary, with trace and causation, and do not emit another error Signal for an incoming `jido.agent_server.error` Signal. Stop safely when error-Signal delivery fails.
- **why:** Error reporting must preserve the commit and must not expose raw values or make a loop.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I10 — Runtime Agent Directive handoff

- **scope:** `Jido.AgentServer.Directive.AgentStart`, `AgentStop`, `AgentSend`, `OwnerSend`
- **must:** Validate local Agent targets, start options, placement, and owner presence before commit. Reject remote start before commit. After commit, start or stop the named runtime Agent, send a Signal to it, or send a Signal to its owner in Directive order.
- **why:** Runtime Agent requests need one admitted post-commit dispatch boundary.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I11 — Independent process start

- **scope:** `Jido.AgentServer.Directive.ProcessStart`
- **must:** Require a Jido instance and a valid OTP child specification before commit. After commit, start the process under the selected instance supervisor. Accept normal OTP start and ignore results, report start failure as an effect failure, and do not claim AgentServer ownership of the process lifetime.
- **why:** Application process startup is an effect, but its lifetime belongs to the instance supervisor.
- **kind:** functional
- **status:** active

### jido.agent_server.effects.I12 — Public runtime Directive API

- **scope:** `Jido.AgentServer.Directive` and its built-in result records
- **must:** Document and type only the supported constructors, option sets, restart policies, and result records. Reject unknown or duplicate constructor options. Keep validation hooks and record schemas hidden. Keep `Jido.AgentServer.Effects` and `Jido.Dispatch.Preparation` internal. Do not add an effects DSL.
- **why:** Agent code needs one stable way to request post-commit work without depending on the effect engine.
- **kind:** functional
- **status:** active
