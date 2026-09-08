> Seam review entry point. This document is pending approval.

# 02 — Agent authoring

## Briefing

Jido supports Agent modules, Spark blocks, direct map and keyword data,
Builder, and Codec documents. These forms use one Agent constructor, but some
source features exist only for modules. The recommended target keeps all
supported forms. It defines parity as equality of the canonical Agent
definition, makes `agent/0` the module authority, keeps generated interfaces as
module API, and gives Codec a clear portable subset. It also adds compatible
definition-revision propagation from the pending Agent seam.

All requirements and decisions are pending approval. The prerequisite seams
are also pending drafts.

## Why this seam exists

- Owner: the `Jido.Agent` authoring boundary.
- Owns: Spark Agent syntax, inline route Actions, generated interfaces,
  Builder, Agent and Plugin Codecs, trusted Registry use, authoring
  normalization, validation timing, and static Agent extensions.
- Does not own: Agent value fields, Action or Flow execution, Signal routing
  semantics, Plugin runtime behavior, checkpoints, restore, commit, or Agent
  Server lifecycle.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Forms | Module, Spark, direct data, Builder, and Codec are supported. | Keep all forms and one canonical definition result. |
| Module authority | `agent/0` validates `__agent_config__/0`; the private config can remain in input form. | Define `agent/0` as canonical and `__agent_config__/0` as private compiler data. |
| Interfaces | `define` generates Signal and live-call helpers only on modules. | Keep module-only helpers outside definition parity. |
| Codec | Static data uses a trusted Registry and a closed JSON format. Instance encoding validates live state. | Encode the static definition of a definition or instance. Keep nonportable source forms valid but not encodable. |
| Extensions | Spark calls the pure lowerer. Builder and Codec accept lowered data only. | Publish one pure data-lowering boundary and keep runtime ownership out. |
| Revision | No definition revision exists in authoring data. | Preserve the pending Agent-seam revision through every applicable form. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Revision propagation | Module meaning cannot be checked after restore. | One compatible revision value in all applicable authoring forms. | 01 Agent, 02 Agent authoring |
| Parity boundary | Module interfaces and extension syntax can be confused with Agent value parity. | Equality at the canonical definition boundary, with source-only features stated separately. | 02 Agent authoring |
| Codec instance input | Static serialization can fail because instance state is parsed again. | Definition-first static encoding for definitions and instances. | 02 Agent authoring |
| Predicate portability | Direct forms accept closures that Registry cannot encode. | A documented encodable subset and a clear Codec error. | 02 Agent authoring, `jido_signal` |
| Data extension entry | Pure lowering exists but is not a documented data-authoring contract. | One public pure lowerer; Builder and Codec consume lowered data. | 02 Agent authoring |

## Decisions requested

1. **Supported forms:** Keep module, Spark, direct data, Builder, Codec, and
   neutral definitions.
2. **Parity:** Define parity as canonical Agent-definition equality. Keep
   generated interfaces as module API.
3. **Codec input:** Accept definitions and instances, but encode only the
   validated neutral definition.
4. **Extensions:** Publish pure lowering for data users. Do not add extension
   entities to Builder or Codec documents.
5. **Portable subset:** Keep runtime route closures valid for direct use, but
   require Registry-backed external captures for Codec.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), and
  [01 Agent](../01_agent/alignment.md). All are pending draft prerequisites.
- Dependents: 04 Turn evaluation, 05 Plugins, 07 Persistence, 08 Agent Server,
  11 Topology control plane, and 99 Delivery.
- Blockers: prerequisite approval, final definition-revision rules, and the
  final authoring error contract.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
