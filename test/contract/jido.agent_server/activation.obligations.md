---
modules:
  - Jido.AgentServer.Supervisor
  - Jido.AgentServer.RegistrationGuard
  - Jido.AgentServer.RegistryWorker
---

## Purpose

Protect one local AgentServer activation root, its instance registration, and
its memory-only recovery boundary. The activation owns the OTP root and the
runtime records that must survive worker replacement.

This component does not own Turn evaluation, Plugin callback rules, durable
storage, Ref routing, or child-composition behavior.

## Obligations

### jido.agent_server.activation.I1 — Activation root identity and lifetime

- **scope:** `Jido.AgentServer.child_spec/1`, `Jido.AgentServer.start_link/1`, `Jido.AgentServer.Supervisor`
- **must:** Use one stable child identity for the instance, partition, and Agent ID. Supervise one request worker under one activation root with the correct OTP child type. Restart after abnormal worker loss, but do not restart after explicit stop. Return the worker from public startup and stop the complete activation on explicit stop. Keep bare worker startup separate from an activation.
- **why:** Public worker identity and OTP ownership must stay distinct.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I2 — Selected instance ownership

- **scope:** `Jido.AgentServer.start/1`, `Jido.AgentServer.RegistrationGuard`
- **must:** Attach the activation to the selected live instance supervisor, Runner, Registry, and registration guard. Claim at most one live activation per instance, partition, and Agent ID. Isolate equal identities across instances and partitions. Reject cross-instance Runners and partitions without an instance. Stop the worker when its Registry or registration guard is lost.
- **why:** An activation must not run under an uncertain instance owner.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I3 — Fixed runtime defaults

- **scope:** `Jido.AgentServer.start/1`
- **must:** Read the selected instance's validated AgentServer defaults once during startup. Let explicit server options override instance settings and let instance `turn_timeout` override application and built-in defaults. Keep the resolved values fixed for that worker lifetime.
- **why:** Worker recovery must use one selected runtime configuration.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I4 — Registration and readiness publication

- **scope:** `Jido.AgentServer.start_link/1`, `Jido.AgentServer.await_ready/2`, `Jido.AgentServer.alive?/1`
- **must:** Support valid local, global, and via OTP names without treating an unrelated process as an AgentServer. Publish an instance registration as starting until worker cleanup, state restore, and required Plugin readiness finish. Publish ready only after all startup gates pass. Keep reads available while starting and reject admitted work as not ready. A caller readiness timeout must not cancel startup.
- **why:** Lookup must not expose an activation as ready before it can accept work.
- **kind:** ordering
- **status:** active

### jido.agent_server.activation.I5 — Recovery group and cleanup barrier

- **scope:** `Jido.AgentServer.Supervisor`
- **must:** Recover the worker and required Plugin roots as one `:one_for_all` group. Use fresh worker and resource references. Close the previous Runic execution scope before admission opens, including when its Worker has already stopped. Keep admission closed while cleanup is uncertain. Stop the activation when cleanup exceeds the readiness budget or restart intensity. Ignore stale startup results and deadlines.
- **why:** A replacement worker must not overlap work from the lost worker.
- **kind:** ordering
- **status:** active

### jido.agent_server.activation.I6 — Local checkpoint publication

- **scope:** `Jido.AgentServer.Supervisor.publish_checkpoint/3`
- **must:** Seed the local checkpoint with the complete initial Agent and revision zero. Atomically replace only the expected preceding revision with the complete validated candidate and next revision before local commit success is visible. Advance once for successful unchanged state. Do not change the checkpoint after failed, invalid, timed-out, or cancelled work.
- **why:** Local recovery must select one complete committed value.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I7 — Local checkpoint restore and lifetime

- **scope:** `Jido.AgentServer.Supervisor`
- **must:** In memory-only mode, restore the last published Agent and revision before Plugin initialization or readiness. Validate the complete Agent, nonnegative revision, Agent ID, module, and definition. Stop recovery for a missing, corrupt, or incompatible checkpoint. Store no portable serialization, transient context, or runtime record in the checkpoint. Delete it with the activation. A new activation starts from its supplied Agent. A bare worker has no activation checkpoint.
- **why:** A local checkpoint must not become an accidental durable record.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I8 — Checkpoint crash and failure boundary

- **scope:** `Jido.AgentServer`, `Jido.AgentServer.Supervisor.publish_checkpoint/3`
- **must:** Restore the previous commit after a crash before publication and the new commit after a crash following publication. Do not replay the accepted Turn, post-commit hooks, or Directives. Reject checkpoint conflicts or unavailable tables without reporting commit success or running post-commit work. Stop the activation with confirmed execution cleanup.
- **why:** A lost reply or failed local publication must not create two commit outcomes.
- **kind:** ordering
- **status:** active

### jido.agent_server.activation.I9 — Activation control records

- **scope:** `Jido.AgentServer.attach/3`, `Jido.AgentServer.detach/3`, `Jido.AgentServer.quiesce/2`, `Jido.AgentServer.resume/2`
- **must:** Keep closed or blocked admission and attached-owner identities in activation-owned runtime records across worker replacement. Rebuild one monitor per owner before readiness. Do not replay an interrupted control or reopen admission during recovery. Make attach and detach idempotent. Match the exact owner monitor without consuming another lifecycle event for the same PID. Keep these records out of the Agent checkpoint.
- **why:** Worker replacement must preserve activation control state without changing Agent state.
- **kind:** functional
- **status:** active

### jido.agent_server.activation.I10 — Idle deadline

- **scope:** `Jido.AgentServer.touch/1`, activation idle control
- **must:** Disable idle expiry by default. Accept one finite idle timeout from selected startup settings. Start a new budget only while the worker is ready, idle, admission is open, and no owner is attached. Restart it after touch, accepted work, the last detach, or owner loss. Do not stop active work or post-commit effects. Ignore stale timer tokens. Reads do not count as activity.
- **why:** Idle shutdown must follow current activation activity and ownership.
- **kind:** ordering
- **status:** active

### jido.agent_server.activation.I11 — Activation-owned child records

- **scope:** `Jido.AgentServer.Supervisor`
- **must:** Keep child tag reservations and relationship records in the activation table, outside Agent state and local checkpoints. Fence replacement by reservation token. Remove owned child records when the worker recovery group starts again because the owned DynamicSupervisor and its children have stopped. Keep child behavior and adoption rules in `jido.agent_server.composition`.
- **why:** Recovery must not retain a record for a stopped activation-owned child.
- **kind:** functional
- **status:** active
