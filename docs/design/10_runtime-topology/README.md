> Seam review entry point. This document is pending approval.

# 10 — Runtime topology

## Briefing

Jido already has a useful local OTP runtime. One instance starts five local
services under `:one_for_one`. Agent Servers and Plugin runtime wrappers are
peers in one Dynamic Supervisor. Execution and Plugin runtime work have explicit
owner coupling. Logical child Directives support local children and explicit
placement on a known Erlang node. The recommended V3 target keeps this topology first. It adds
complete failure-coupling proof, owner-bound Plugin readiness, coherent Plugin
runtime replacement input, and additive integration with local Agent Ref
resolution. It does not add cluster discovery, automatic placement, failover,
leases, fencing, or live topology control.

The [design review index](../README.md#document-review-status) is the source of
truth for approval. All requirements and decisions in this seam are pending.

## Why this seam exists

- Owner: the local Jido OTP runtime topology below one Jido instance.
- Owns: runtime process placement, supervisor membership, child ownership,
  restart coupling, shutdown coupling, logical runtime relationships, explicit
  known-node child ownership, and local-versus-remote limits.
- Does not own: Agent state, Turn semantics, persistence records, Agent Ref
  fields, instance facade names, desired topology, repair policy, transport,
  cluster authority, or application supervision above the Jido instance.

## Current and target state

| Area | Current | Recommended target |
| --- | --- | --- |
| Instance tree | Task Supervisor, Registry, Runtime Store, Spawn Registry, and Agent Dynamic Supervisor use `:one_for_one`. | Keep this five-child first-stage tree and prove each failure boundary. |
| Agent placement | Agent Servers are direct peers. Managed Servers default to `:transient`. | Keep direct peers and current restart sources. Keep desired reactivation outside this seam. |
| Plugin placement | Temporary wrappers share the Agent pool. Each wrapper owns a private supervisor with one permanent Plugin root. | Keep this placement first. Add coherent state-version input and owner-death proof. |
| Owned work | Execution, admission, Plugin Directive, and error-policy work use bounded processes. Initial readiness and error-policy delivery are not linked to abrupt owner death. | Require all owned work to stop when its owner stops. |
| Nondurable recovery | An abnormal Server restart restores the latest instance checkpoint. A clean stop removes it. | Keep this same-instance rule and state that instance loss removes the checkpoint. |
| Logical children | Parent and child handles are private runtime data. Parent bindings and spawn receipts use Runtime Store. | Keep the relationship contract and replace handles through Ref resolution only after seams 03 and 09 are ready. |
| Remote children | A known target node owns the child process. There is no local fallback. Timeouts can be indeterminate. | Keep this bounded contract. Do not claim discovery, failover, or exclusive cluster authority. |
| Topology control | A separate application-supervised Controller activates and repairs one static local target. | Keep desired state, readiness policy, and repair in seam 11. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Failure matrix is incomplete | The five-child strategy has no full restart-coupling proof. | Tested effects for each standard child failure and full instance shutdown. | 09 Jido instance, 10 Runtime topology |
| Work ownership is incomplete | Abrupt Agent death can leave initial readiness or error-policy delivery work until it finishes. | Every owned worker stops with its Agent Server. | 08 Agent Server, 10 Runtime topology |
| Plugin replacement input is split | A replacement reads current state after it starts and has no matching version input. | One committed Plugin state and matching state version for each generation. | 05 Plugins, 08 Agent Server, 10 Runtime topology |
| Ref integration is missing | Child delivery and relationships keep replaceable PIDs. | Add local Ref resolution without removing current PID paths. | 03 Identity, 09 Jido instance, 10 Runtime topology |
| Cluster authority is absent | A known-node start does not prevent two writers or choose recovery placement. | Keep the claim out of core until an explicit external authority contract exists. | 90 Package boundaries, future cluster owner |
| Control-plane boundary needs one contract | Runtime ownership and desired-state repair can be confused. | Seam 10 supplies components; seam 11 owns target activation and repair. | 10 Runtime topology, 11 Control plane |

## Decisions requested

1. **First-stage instance topology:** Keep the current five children,
   `:one_for_one`, and one Agent Dynamic Supervisor.
2. **Plugin placement:** Keep temporary Plugin wrappers beside Agent Servers for
   V3. Require a permanent internal Plugin root and coherent replacement input.
3. **Nondurable restart:** Keep latest-commit recovery only while the same Jido
   instance stays live.
4. **Logical relationships:** Keep private runtime child records, Runtime Store
   parent bindings, and current child Directives during Ref migration.
5. **Remote scope:** Keep explicit known-node placement, no local fallback, and
   indeterminate result handling. Defer discovery, failover, leases, fencing,
   and exclusive cluster ownership.
6. **Control-plane split:** Keep static activation and repair in seam 11 and
   outside the Jido instance supervisor.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md),
  [07 Persistence](../07_persistence/alignment.md),
  [08 Agent Server](../08_agent-server/alignment.md), and
  [09 Jido instance](../09_jido-instance/alignment.md). All are pending drafts.
- Dependents: 11 Topology control plane, 13 Observability, and 99 Delivery.
- Blockers: prerequisite approval, Ref and namespace implementation, Plugin
  replacement input, revision-zero durable creation, and the final cluster
  authority owner.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
