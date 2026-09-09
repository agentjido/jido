> Seam review entry point. The implementation direction was selected on
> 2026-09-10. Seam 09 now supplies the Ref-first instance controls.

# 08 — Agent Server

## Briefing

`Jido.AgentServer` is the live owner for one Agent activation. It serializes
Signals, keeps one committed Agent and state version, applies one pre-commit
Turn timeout, commits before Directive handling, and restores the last runtime
or durable checkpoint. Public instance lookup reports the Server only after
Plugin readiness and any required revision-zero write. Every Plugin runtime
generation gets one immutable owned-state and state-version pair. This does not
make Agent Server the
owner of Agent meaning, Turn evaluation, storage semantics, Jido instance
policy, or topology policy.

Code and executable tests are canonical for current behavior.

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

## Implemented state and retained limits

| Area | Implemented contract | Retained limit |
| --- | --- | --- |
| Live owner | One `:gen_statem` owns one Agent, one version, and at most one active Turn. | Keep one serialized commit owner per activation. |
| Startup | Construct or restore, validate, reserve identity, start Plugin children, await readiness, confirm revision-zero creation, and publish `:ready`. | Keep this order. The seam-09 Ref facade preserves it. |
| Identity | Public Server operations use PID and name. Compatible instance APIs use ID and partition. | Seam 09 adds local Ref resolution. Keep supported PID/name operations during migration. |
| Admission | OTP postpones busy Signals. A token set limits callbacks already seen by the state machine. | Keep OTP ordering and state the mailbox limit accurately. Add stable overload and admission errors. |
| Turn control | Admission and execution are cancellable. One `turn_timeout` covers active work until commit starts. | Keep caller wait, persistence, readiness, and Directive limits separate. |
| Commit | Runtime or durable checkpoint succeeds before complete state replacement, reply, and Directives. | Keep the order. Remove write authority after every required persistence write error. |
| Plugins | Every runtime start and replacement receives one matching committed Plugin state and Agent state version. | Keep runtime handles private and retain live state pull for later reconciliation. |
| Effects and children | Directives run in order after commit. Child and runtime handles stay outside Agent state. | Keep this behavior. Treat uncertain child effects as runtime results, not topology or durability claims. |
| Stop and observation | Current status is a map with five phases. Outcomes use five stages. Debug events and several error policies are public. | Keep these paths during migration. Define authority-loss stop and transient Plugin degradation without adding topology policy. |
| Code revision | Agent definitions have no revision. Agent Server has no hot-state migration callback. | Enforce the prerequisite definition revision at construction or restore. Do not claim that it pins loaded Action or Flow code. |

## Remaining dependent work

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Runtime identity | PID, ID, partition, and storage identity do not share one Ref. | Additive Ref resolution with current controls retained. | 03 Identity, 08 Agent Server, 09 Jido instance |
| Public contracts | Maps, atoms, tuples, and executable error policy coexist. | Owner-defined values, stable errors, and staged compatibility. | 08 Agent Server, 12 Errors, 13 Observability |

## Selected decisions

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
- Completed input: Ref namespace binding and the additive instance facade in
  seam 09. Deferred inputs are any later observation projection in seam 13 and cross-package proof
  in seam 99. Hot private-state migration is not a V3 claim.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
