> Seam review entry point. This document is pending approval.

# 08 — Agent Server

## Briefing

`Jido.AgentServer` is the live owner for one Agent activation. Current code
already serializes Signals, keeps one committed Agent and state version, runs
admission and executable work without blocking control calls, commits before
Directive handling, and restores the last runtime or durable checkpoint. The
recommended target keeps this base. It adds the prerequisite stable-identity,
initial-durable-record, all-write-error authority, whole-Turn limit, and
coherent Plugin-runtime restart contracts. It does not make Agent Server the
owner of Agent meaning, Turn evaluation, storage semantics, Jido instance
policy, or topology policy.

All requirements and decisions are pending approval. Code and executable tests
remain canonical for current behavior.

## Why this seam exists

- Owner: `Jido.AgentServer` and its private live activation state machine.
- Owns: serialized admission, one active Turn, live committed state and state
  version, task and cancellation control, commit coordination, post-commit
  Directive settlement, Plugin runtime links, child-effect coordination,
  hibernation, and process stop behavior.
- Does not own: Agent construction semantics, route or candidate semantics,
  Plugin facet contracts, persistence record meaning, stable Ref fields,
  instance namespace or lookup policy, placement, cluster authority,
  transport, or application architecture.

## Current and target state

| Area | Current | Recommended target |
| --- | --- | --- |
| Live owner | One `:gen_statem` owns one Agent, one version, and at most one active Turn. | Keep one serialized commit owner per activation. |
| Startup | Construct or restore, validate, start Plugin children, await readiness, then publish. New persistent state has no revision-zero write. | Keep canonical construction. For persistence, publish only after Plugin readiness and a create-only revision-zero write. |
| Identity | Public operations use PID, name, ID, instance, and partition values. | Add Ref-based resolution in the instance seam. Keep supported PID/name operations during migration. |
| Admission | OTP postpones busy Signals. A token set limits callbacks already seen by the state machine. | Keep OTP ordering and state the mailbox limit accurately. Add stable overload and admission errors. |
| Turn control | Admission and execution are cancellable. Admission reuses `directive_timeout`; native execution has no Server-wide Turn limit. | Use one pre-commit Turn limit and keep caller wait, persistence, readiness, and Directive limits separate. |
| Commit | Runtime or durable checkpoint succeeds before complete state replacement, reply, and Directives. | Keep the order. Remove write authority after every required persistence write error. |
| Plugins | Runtimes start before readiness and can restart from fresh owned state, but state and version are not one input. | Give every start or replacement one matching committed Plugin state and Agent state version. |
| Effects and children | Directives run in order after commit. Child and runtime handles stay outside Agent state. | Keep this behavior. Treat uncertain child effects as runtime results, not topology or durability claims. |
| Stop and observation | Current status is a map with five phases. Outcomes use five stages. Debug events and several error policies are public. | Keep these paths during migration. Define authority-loss stop and transient Plugin degradation without adding topology policy. |
| Code revision | Agent definitions have no revision. Agent Server has no hot-state migration callback. | Enforce the prerequisite definition revision at construction or restore. Do not claim that it pins loaded Action or Flow code. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Initial durable boundary | Ready can mean that no durable record exists. | Revision-zero create before publication. | 07 Persistence, 08 Agent Server |
| Write authority | Confirmed conflicts can continue under error policy. | One stop-before-next-Turn rule for every required write error. | 06 Commit, 07 Persistence, 08 Agent Server |
| Runtime identity | PID, ID, partition, and storage identity do not share one Ref. | Additive Ref resolution with current controls retained. | 03 Identity, 08 Agent Server, 09 Jido instance |
| Turn limit | Admission and execution do not have one Server-owned pre-commit limit. | Distinct, testable operation deadlines and stale-result rejection. | 08 Agent Server, with 04 Turn evaluation |
| Plugin replacement | Restart reads current state but not one state-version pair. | Coherent bootstrap input for every runtime generation. | 05 Plugins, 08 Agent Server |
| Public contracts | Maps, atoms, tuples, and executable error policy coexist. | Owner-defined values, stable errors, and staged compatibility. | 08 Agent Server, 12 Errors, 13 Observability |

## Decisions requested

1. **Compatibility API:** Keep documented PID/name Agent Server operations,
   status, Outcomes, and debug paths until an additive Ref-first instance
   facade has proof and a later removal is approved.
2. **Public phases:** Keep `initializing`, `idle`, `admitting`, `running`, and
   `directing` in the status compatibility map. Keep current Outcome stages
   until seam 13 approves a migration.
3. **Turn limit:** Add one Server-owned limit for all cancellable pre-commit
   work. Keep it separate from caller wait and post-commit limits.
4. **Write authority:** Stop the activation after every required persistence
   write error. Require a new activation to restore authoritative state.
5. **Plugin degradation:** Let a replacing Plugin runtime be visible as
   restarting and keep inspection responsive. Never substitute a process-free
   handler for a required runtime. Stop if replacement readiness fails.
6. **Error policy:** Keep current policies during migration, but do not let any
   policy override persistence authority, commit order, or Directive atomicity.
7. **Code revision:** Use definition revision only as a construction and
   restore check. Do not promise a snapshot of loaded executable code or a hot
   state migration until those owners define one.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md), and
  [07 Persistence](../07_persistence/alignment.md). All are pending drafts.
- Related input: [02 Agent authoring](../02_agent-authoring/design.md) defines
  canonical construction and generated live-helper delegation.
- Dependents: 09 Jido instance, 10 Runtime topology, 11 Topology control plane,
  13 Observability, and 99 Delivery.
- Blockers: prerequisite approval, Ref and namespace binding, the all-write-
  error rule, whole-Turn limit details, Plugin bootstrap value names, public
  error migration, and any hot-code state migration contract.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
