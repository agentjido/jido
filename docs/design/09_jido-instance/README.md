> Seam review entry point. This document is pending approval.

# 09 — Jido instance

## Briefing

A Jido instance is the application-owned local runtime boundary. Current code
already gives it a useful role: it is a standard OTP Supervisor, owns local
runtime services, starts Agent Servers, and provides ID-based lifecycle helpers.
The recommended target keeps this behavior. It adds an optional stable namespace
and a Ref-first facade in compatible stages. It does not make the instance a
global runtime, a transport router, or a topology control plane. It also keeps
the public PID-based Agent Server API until a later approved migration has
replacement proof.

All target requirements and decisions are pending approval. Code remains the
source of truth for current behavior.

## Why this seam exists

- Owner: `Jido`, generated modules that use `Jido`, and the local instance
  supervision boundary.
- Owns: local instance startup, local names, Registry and runtime-service
  isolation, instance configuration, Agent Server publication, local Ref
  resolution, lifecycle facade policy, and the instance persistence default.
- Does not own: Agent or Turn semantics, Agent Server internals, Plugin
  callbacks, persistence records or adapters, Signal routing, transport,
  placement, cluster authority, topology definitions, or topology control.

## Current and target state

| Area | Current | Recommended target |
| --- | --- | --- |
| Runtime role | An atom-named `:one_for_one` Supervisor owns five local services. | Keep the application-owned local Supervisor and document its service and failure boundaries. |
| Configuration | `use Jido` requires `:otp_app`; application config and runtime options merge into an open keyword list. | Keep the merge order, validate instance-owned options before child startup, and add namespace only through a compatible option. |
| Identity | The instance atom scopes Registry, runtime checkpoints, and durable keys. | Bind an optional stable namespace for Agent Ref. Keep local process names separate from durable identity. |
| Lifecycle API | Generated helpers start, find, list, count, stop, hibernate, and thaw by ID, PID, or Server reference. | Keep these helpers and add Ref-first command, control, lifecycle, and inspection paths. |
| Agent Server API | Public PID and name functions are documented and tested. | Keep them supported beside the Ref facade until a separate removal decision. |
| Persistence | A compile-time instance default can be overridden or disabled per Agent. | Preserve this precedence. Validate the default at instance startup and consume seam-07 lifecycle results without redefining them. |
| Extension points | `config/1` is overridable. No child, admission, or lifecycle callback exists. | Keep `config/1`. Defer new callbacks until one concrete use case defines timing, authority, and failure behavior. |
| Scope | Registry and Runtime Store are local. Remote child placement is explicit. | Keep local resolution only. Leave transport, placement, discovery, and write authority to their owners. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No stable namespace or core Ref | Module and instance names still affect identity. | Add stable namespace binding and Ref-first local resolution in compatible stages. | 03 Agent identity, 09 Jido instance, 07 Persistence |
| Incomplete configuration validation | Invalid values can fail only when a child or Agent consumes them. | Validate all instance-owned values before the instance starts children. | 09 Jido instance, 12 Errors |
| No Ref facade | Callers must combine lookup and PID-based operations. | One local lookup and error policy for Ref-first lifecycle, command, control, and inspection. | 09 Jido instance, 08 Agent Server |
| Supervision failure proof is incomplete | Current tests prove child presence, not restart coupling. | Failure-injection evidence for each instance-owned service. | 09 Jido instance |
| Durable lifecycle is incomplete | Initial records, tombstones, and write-authority loss are pending. | Consume one approved persistence and Server lifecycle contract. | 07 Persistence, 08 Agent Server |
| Public errors remain mixed | Instance functions return PIDs, `nil`, atoms, tuples, and errors. | Preserve approved protocol values and normalize failures through seam 12. | 09 Jido instance, 12 Errors |

## Decisions requested

1. **Instance role:** Keep one application-owned local runtime Supervisor and
   facade. Do not create a required global Jido runtime.
2. **Supervision:** Keep the implemented five-service `:one_for_one` tree for
   the first alignment stage. Change its strategy or child placement only with
   failure-coupling evidence.
3. **Stable identity:** Add an optional nonempty namespace. Permit one live
   binding for an exact namespace on one node. Keep module and process names
   separate from Agent Ref.
4. **API migration:** Add Ref-first local operations. Keep current ID, PID,
   name, partition, and direct Agent Server APIs until a later approval.
5. **Persistence precedence:** Keep explicit per-Agent selection or disablement
   above the instance default. Do not add record-valued instance callbacks.
6. **Callbacks:** Keep only the current overridable `config/1` extension now.
   Defer `children/1`, admission, and lifecycle callbacks.
7. **Boundary:** Keep instance operations local. Do not make namespace binding
   a directory, placement service, transport, lease, or fencing system.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [05 Plugins](../05_plugins/alignment.md),
  [06 Commit and effects](../06_commit-and-effects/alignment.md),
  [07 Persistence](../07_persistence/alignment.md), and
  [08 Agent Server](../08_agent-server/alignment.md). All are pending drafts.
- Related inputs: [02 Agent authoring](../02_agent-authoring/design.md) and
  [04 Turn evaluation](../04_turn-evaluation/design.md).
- Dependents: 10 Runtime topology, 11 Topology control plane, 13 Observability,
  and 99 Delivery.
- Blockers: prerequisite approval; namespace and partition migration; Ref API
  names; persistence record migration; and stable public error codes.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
