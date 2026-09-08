> Seam review entry point. This document is pending approval.

# 05 — Plugins

## Briefing

Jido has a useful Plugin base: ordered declarations, one owned state key per
Plugin, unique Directive ownership, direct and live callback paths, optional
runtime children, post-commit dispatch, and a Scheduler with durable pending
work. The current `Jido.Plugin` behavior mixes pure Agent work with live Agent
Server work. It also gives preparation callbacks the complete Agent and one
shared command value. The recommended target keeps the supported behavior but
normalizes one Plugin declaration into owner-specific Agent, Agent Server,
Persistence, and Topology facets. It keeps state in the combined Agent state
map, fixes route selection before Plugin preparation, isolates Plugin inputs,
and gives each replacement runtime one committed state and version snapshot.

All requirements and decisions are pending approval. Canonical code still
defines current behavior.

## Why this seam exists

- Owner: the Plugin declaration, normalization, and owner-specific extension
  contracts.
- Owns: Plugin declaration order, facet selection, Plugin state and Directive
  ownership metadata, bounded callback authority, optional scheduled-capability
  contracts, and Plugin compatibility rules.
- Does not own: Agent domain state, route precedence, executable work, live
  commit, Agent Server runtime policy, persistence records or adapters,
  Topology activation, durable workflow orchestration, or transport.

## Current and target state

| Area | Canonical current state | Recommended target |
| --- | --- | --- |
| Declaration | A module or `{module, keyword}` list becomes private mixed Specs. | Keep the declaration form and order. Normalize one package manifest into owner-specific Specs. |
| State | One atom key per stateful Plugin is part of the complete Agent state map. | Keep the combined map, unique keys, executable write protection, and complete-slice replacement. |
| Turn input | `prepare/2` receives the complete Agent and one shared Command. Routing follows preparation. | Select the Turn from the source Signal first. Give each Plugin a declared Agent view and separate prepared input. |
| Live callbacks | Admission, outbound Signal changes, runtime lifecycle, and dispatch share the mixed behavior. | Move them to the Agent Server facet and keep Agent Server ownership of execution, limits, and failure policy. |
| Runtime start | Init has identity and options. A runtime can later read owned state without its version. | Start or replace a runtime with one matching committed owned-state and state-version snapshot. |
| Persistence | Whole-Agent checkpoint callbacks store the combined state. | Keep the default path. Add optional pure owned-slice conversion only after the custom-checkpoint rule is approved. |
| Scheduling | Scheduler has stable occurrence IDs and optional durable one-pending-item delivery. | Preserve the behavior and its duplicate-work limit through facet migration. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Mixed callback ownership | Pure Agent code and live runtime code use one behavior and Spec. | One declaration with owner-specific facets and no foreign fields in an owner Spec. | 05 Plugins |
| Unbounded Turn data | A Plugin can read complete Agent state and replace shared preparation data. | Declared Agent views, isolated Plugin inputs, and bounded contributions. | 05 Plugins, 04 Turn evaluation |
| Route order conflict | Preparation can change which executable runs. | Fixed source-Signal selection before preparation, with no second route lookup. | 04 Turn evaluation, 05 Plugins |
| Incomplete runtime bootstrap | State and version are not read as one value. | One coherent snapshot for first start and every replacement. | 05 Plugins, 08 Agent Server, 10 Runtime topology |
| Optional facet contracts are absent | Persistence and Topology extensions have no bounded Plugin contract. | Pure owned-slice conversion and pure canonical plan contribution, with owner-seam limits. | 05 Plugins, 07 Persistence, 11 Topology control plane |
| Public error and portability gaps | Callback results and state acceptance still use mixed errors and late checks. | Seam-12 errors and early portable-value checks at Plugin-owned boundaries. | 05 Plugins, 12 Errors and contracts |
| Migration proof is incomplete | Built-ins and external Plugins use the mixed behavior. | Compatibility normalization and parity evidence before legacy callback removal. | 05 Plugins, 99 Delivery |

## Decisions requested

1. **Facet model:** Approve one callback-free package manifest with at most one
   Agent, Agent Server, Persistence, and Topology facet.
   Effect: each Jido owner controls its own execution and failure rules.
2. **State model:** Keep Plugin-owned keys in the complete Agent state map.
   Effect: no checkpoint or Agent value split is required.
3. **Turn isolation:** Approve declared observations, per-Plugin prepared input,
   and bounded contributions after fixed route selection.
   Effect: a Plugin cannot read or replace another owner's Turn data.
4. **Directive contribution:** Let an Agent facet replace its owned state and
   append only Directives that it owns.
   Effect: contribution stays bounded and deterministic.
5. **Live behavior:** Keep admission and reverse-order outbound Signal
   preparation in the Agent Server facet. Treat state-only Directives as fully
   handled after their successful pre-commit reduction.
   Effect: current live behavior has a direct migration path.
6. **Runtime bootstrap:** Add one immutable owned-state and state-version input
   for first start and every replacement.
   Effect: readiness uses a coherent committed view.
7. **Custom checkpoints:** Let complete custom Agent checkpoints bypass a
   Persistence facet during the first compatibility stage.
   Effect: existing callbacks remain valid while a later domain-only callback
   design stays open.
8. **Scheduler:** Keep the current occurrence-ID and durable delivery contract.
   Effect: facet migration cannot weaken recovery or change existing IDs.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md), and
  [04 Turn evaluation](../04_turn-evaluation/alignment.md). All are pending
  draft prerequisites.
- Related inputs: [02 Agent authoring](../02_agent-authoring/design.md) preserves
  ordered canonical Plugin declarations. [03 Agent identity](../03_agent-identity/design.md)
  keeps Agent Ref separate from module, runtime handle, and state version.
- Dependents: 06 Commit and effects, 07 Persistence, 08 Agent Server, 10 Runtime
  topology, 11 Topology control plane, 13 Observability, and 99 Delivery.
- Blockers: prerequisite approval, exact public facet and callback value names,
  custom-checkpoint composition, and runtime identity fields.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
