> Approved seam review entry point. Dependent owner-seam work remains open.

# 01 — Agent

## Briefing

`Jido.Agent` already has a strong V3 base. One immutable struct has two valid
forms: a neutral definition and an instance. An instance has one combined state
map. That map contains domain state and Plugin-owned state. Direct `cmd/3`
evaluation returns a candidate Agent and Directives without a process or commit.
This seam keeps those contracts. It also keeps Builder, Codec, custom routing,
and custom checkpoint callbacks. The working-tree implementation adds a
compatible module-owned `vsn` and rejects nonportable state at Agent acceptance
boundaries. The contract and its implementation evidence were approved on
2026-09-09.

## Why this seam exists

- Owner: `Jido.Agent` and its private validation and command support.
- Owns: the Agent definition and instance values, combined state validation,
  immutable data changes, direct evaluation entry point, and Agent checkpoint
  and restore boundary.
- Does not own: route selection order, Agent Ref, Plugin facets and callback
  authority, persistence records, commits, Agent Server state, or runtime
  topology.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Agent forms | One struct supports a neutral definition and an instance. | Keep both forms and reject half-instances. |
| State | One complete map includes domain and Plugin-owned fields. | Keep one map and keep separate write owners. |
| Direct execution | `cmd/3` returns a candidate Agent and Directives. | Keep this process-free evaluation contract. |
| Authoring | Module DSL, direct data, Builder, and Codec use shared validation. | Keep all forms and one normalized definition contract. |
| Checkpoints | Version-1 maps and complete custom callbacks are supported. | Keep them readable, write version 2 for generated modules, and wrap new custom payloads in a core-owned revision envelope. |
| Portable state | Persistence rejects nonportable records. | Reject nonportable state when the Agent accepts it and again at persistence. Keep static direct definitions unrestricted in memory. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Dependent authoring adoption | Seam 02 must use the approved `vsn` contract in its own final design. | Review and approve the dependent authoring seam. | 02 Agent authoring |
| Persistence integration | Seam 07 owns storage records beyond the Agent checkpoint map. | Review the approved Agent checkpoint contract during persistence approval. | 07 Persistence |
| Error normalization | Callback fault normalization remains outside the implemented Agent scope. | Finish the shared error matrix without changing the approved Agent value or checkpoint contract. | 12 Errors |
| Package compatibility | Package release gates remain owned by the package seam. | Prove the compatible V3 package release set. | 90 Package boundaries |

## Approved decisions

1. **Retained Agent model:** Keep two Agent forms, one combined state map,
   direct execution, Builder, Codec, custom routing, and checkpoint callbacks.
   Effect: no current supported Agent path is removed in this seam.
2. **Agent `vsn`:** Use `vsn` as the canonical field. Use `1` as the
   default for existing `use Jido.Agent` modules and allow unversioned direct
   definitions.
   Effect: module authors get a compatible restore gate.
3. **Checkpoint evolution:** Use a version-2 default map for versioned
   module definitions while version 1 and custom callbacks stay supported.
   Effect: restore can check module meaning without a forced checkpoint struct.
4. **Portable state:** Add early state checks after a compatibility audit
   and use the error contract from seam 12.
   Effect: direct, live, and persistent paths accept the same portable state.

## Additional approved decisions

1. **Custom checkpoint envelope:** Jido wraps a new opaque custom callback
   payload in a versioned core-owned `agent_module` and `vsn` envelope. Restore
   also keeps the legacy raw-map read path.
2. **Direct durable definitions:** Direct definitions stay unrestricted in
   memory. The default checkpoint supports only the portable embedded subset.
   Other definitions get a typed portability error and need a generated module
   or a custom durable form.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md), and
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md). Overview
  is approved. Package and error contracts remain pending.
- Dependents: 02 Agent authoring, 03 Agent identity, 04 Turn evaluation,
  05 Plugins, 07 Persistence, and 08 Agent Server.
- The pending package and error seams are explicit downstream assumptions.
  They do not block the approved Agent contract. A later conflicting contract
  requires a reviewed migration.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
