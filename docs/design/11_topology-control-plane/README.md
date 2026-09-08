> Seam review entry point. This document is pending approval.

# 11 — Topology control plane

## Briefing

Jido core has a static local Topology system. It validates definitions and
plans, starts Agents and Buses on one Jido instance, waits for readiness, and
repairs the same fixed target. It has no distributed control plane. The
recommended target keeps this local contract in core and defines an optional
control-plane contract for an application or integration package. That control
plane can consume membership and authority services, place stable Agent Refs,
coordinate handoff and recovery, and expose operator controls. It must use
public Jido boundaries. It must not claim exclusive ownership unless stale
owners are fenced at the commit boundary.

All target requirements are pending approval. Code and executable tests define
current behavior.

## Why this seam exists

- Owner: `Jido.Topology` and `Jido.Topology.Controller` own static local
  topology. An optional application or ecosystem integration owns distributed
  control-plane policy.
- Owns: the boundary between desired placement and local activation, inputs
  from membership and authority services, placement decisions, handoff and
  recovery coordination, and operator control semantics.
- Does not own: the local OTP process tree, Agent state, Turn evaluation,
  persistence record meaning, cluster membership implementation, consensus,
  transport, deployment, or application policy.

## Current and target state

| Area | Current | Recommended target |
| --- | --- | --- |
| Local Topology | Static definitions and plans; one local Controller repairs one fixed target. | Keep this core contract and its public APIs. |
| Control plane | No distributed control-plane module or service exists. | Add only an optional external contract that uses public Jido operations. |
| Membership and discovery | Core local Registry and explicit known-node child placement only. | Consume a provider-owned, generation-tagged membership view as input. Do not treat membership as authority. |
| Ownership | Local names and persistence CAS detect some conflicts. | Require an external authority grant and stale-epoch fencing before any exclusive-owner or automatic-failover claim. |
| Placement | A caller can request one known Erlang node for an owned child. | Select eligible nodes from declared constraints, capacity, membership, and authority state. |
| Handoff and recovery | No Agent handoff, rebalance, or automatic recovery contract exists. | Use idempotent operations, stable Refs, durable restore, new authority epochs, and explicit partial-failure results. |
| Partitions | Core defines no network-partition policy. | Stop new mutations when authority cannot be confirmed; reconcile to the highest valid epoch after recovery. |
| Operations | Local Controller status and manual repair exist. | Add bounded status plus authenticated cordon, drain, move, rebalance, suspend, resume, and preview operations. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No stable Ref or namespace | Placement cannot name one Agent across nodes. | Approved Ref, namespace binding, and local resolution. | 03 Agent identity, 09 Jido instance |
| No authority or fence input | Two nodes can run the same logical Agent. | Authority grants with monotonically increasing epochs that every write owner enforces. | 06 Commit, 07 Persistence, 08 Agent Server, external authority owner |
| No membership or placement contract | A known node is not discovery or scheduling. | Validated provider inputs and deterministic, explainable placement output. | 11 control plane, external cluster owner |
| No handoff or recovery protocol | Restart and failover can overlap or lose intent. | Idempotent state machines with durable operation records and explicit rollback. | 11 control plane, external durable owner |
| Fixed local target | Repair cannot resize or replace a plan. | Keep repair meaning clear; approve live target change separately. | 11 control plane |
| Incomplete observation and controls | Operators cannot prove why placement or authority changed. | Bounded events, status, audit identity, and safe operator actions. | 11 control plane, 13 Observability |

## Decisions requested

1. **Package boundary:** Keep distributed control-plane behavior outside Jido
   core. Effect: core remains a local Agent library.
2. **Local contract:** Keep the current static local Controller and do not call
   `reconcile/2` a target update. Effect: existing applications remain valid.
3. **Authority:** Require a provider-issued monotonically increasing epoch and
   commit-time fencing for exclusive ownership. Effect: a lease or Registry
   entry alone cannot prove safety.
4. **Membership:** Treat membership and health as placement input, not durable
   identity or write authority. Effect: discovery cannot create ownership.
5. **Placement:** Use provider-neutral constraints and capacity data. Effect:
   the design does not select a distributed library.
6. **Handoff and recovery:** Use durable, idempotent operations and restore from
   the approved persistence contract. Effect: retries do not create a second
   logical operation.
7. **Partition policy:** Stop mutation when authority cannot be confirmed.
   Effect: availability does not override fencing.
8. **Operator boundary:** Approve the listed safe control roles and require
   authentication, audit identity, and preview. Effect: force operations cannot
   bypass authority checks.

## Dependencies

- Prerequisites: [Overview](../00_overview/alignment.md),
  [package boundaries](../90_package-boundaries/alignment.md),
  [errors and contracts](../12_errors-and-contracts/alignment.md),
  [Agent](../01_agent/alignment.md), [Agent identity](../03_agent-identity/alignment.md),
  [Plugins](../05_plugins/alignment.md), [persistence](../07_persistence/alignment.md),
  [Agent Server](../08_agent-server/alignment.md),
  [Jido instance](../09_jido-instance/alignment.md), and
  [runtime topology](../10_runtime-topology/alignment.md). Authority and
  recovery also use [commit and effects](../06_commit-and-effects/alignment.md).
- Dependents: 13 Observability and 99 Delivery.
- Blockers: All prerequisite documents are pending approval. Stable Ref,
  namespace, write-authority loss, revision-zero persistence, fencing input,
  authority-provider semantics, and package ownership are not implemented.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
