> Seam review entry point. This document is pending approval.

# 01 — Agent

## Briefing

`Jido.Agent` already has a strong V3 base. One immutable struct has two valid
forms: a neutral definition and an instance. An instance has one combined state
map. That map contains domain state and Plugin-owned state. Direct `cmd/3`
evaluation returns a candidate Agent and Directives without a process or commit.
This seam keeps those contracts. It also keeps Builder, Codec, custom routing,
and custom checkpoint callbacks. The recommended target adds a compatible
definition revision and rejects nonportable state at Agent acceptance
boundaries. Both changes need staged migration and approval.

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
| Checkpoints | Version-1 maps and complete custom callbacks are supported. | Keep them readable and add a versioned revision check without a forced public struct. |
| Portable state | Persistence rejects nonportable records. | Reject nonportable state when the Agent accepts it and again at persistence. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No definition revision | Restore cannot detect changed module meaning. | Add an authoring-compatible revision and an old-checkpoint rule. | 01 Agent, 02 Agent authoring, 07 Persistence |
| Late portability check | Direct or nonpersistent Agents can accept runtime handles. | Add path-aware checks at Agent state acceptance. | 01 Agent, 05 Plugins, 12 Errors |
| Checkpoint text and behavior are not aligned | The default map stores the complete combined state, not domain-only state. | State the current format correctly and define a compatible next format. | 01 Agent, 07 Persistence |
| Prerequisite drafts are pending | Error and package rules can still change. | Approve or replace the assumptions before implementation. | 00 Overview, 90 Package boundaries, 12 Errors |

## Decisions requested

1. **Retained Agent model:** Approve two Agent forms, one combined state map,
   direct execution, Builder, Codec, custom routing, and checkpoint callbacks.
   Effect: no current supported Agent path is removed in this seam.
2. **Definition revision:** Approve revision `1` as the default for existing
   `use Jido.Agent` modules and allow unversioned direct definitions.
   Effect: module authors get a compatible restore gate.
3. **Checkpoint evolution:** Approve a version-2 default map for versioned
   module definitions while version 1 and custom callbacks stay supported.
   Effect: restore can check module meaning without a forced checkpoint struct.
4. **Portable state:** Approve early state checks after a compatibility audit
   and use the error contract from seam 12.
   Effect: direct, live, and persistent paths accept the same portable state.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md), and
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md). All are
  pending draft prerequisites.
- Dependents: 02 Agent authoring, 03 Agent identity, 04 Turn evaluation,
  05 Plugins, 07 Persistence, and 08 Agent Server.
- Blockers: prerequisite approval, the final portable-error path, and the
  version-2 checkpoint migration rule.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
