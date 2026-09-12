> Approved seam review entry point. Dependent owner-seam work remains open.

# 02 — Agent authoring

## Briefing

Jido supports Agent modules, Spark blocks, direct map and keyword data,
Builder, and Codec documents. These forms use one Agent constructor, but some
source features exist only for modules. The aligned target keeps all
supported forms. It defines parity as equality of the canonical Agent
definition, makes `definition/0` the module authority, keeps generated interfaces as
module API, and gives Codec a clear portable subset. The current implementation
now preserves the Agent `vsn`, starts Builder module input from
`definition/0`, encodes instances from their neutral definitions, and publishes the
pure data extension lowerer. One requirement-mapped suite proves the common
definition and instance boundary for keyword-only and Spark-block modules. The
contract and its implementation evidence are approved.

The Overview and Agent prerequisite seams are approved. Package-boundary and
shared-error work remain explicit assumptions and still require their own
review.

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
| Module authority | `definition/0` is canonical. Builder module input reads it. The private config can remain in input form. | Keep `definition/0` as canonical and `__agent_config__/0` as private compiler data. |
| Interfaces | `define` generates Signal and live-call helpers only on modules. | Keep module-only helpers outside definition parity. |
| Codec | Static data uses a trusted Registry and a closed JSON format. Instance encoding derives the neutral definition and does not parse live state. | Keep definition-first encoding. Keep nonportable source forms valid but not encodable. |
| Extensions | Spark and data users can call the documented pure lowerer. Builder and Codec accept lowered data only. | Keep one pure data-lowering boundary and keep runtime ownership out. |
| Agent `vsn` | Generated modules, direct data, Builder, and Codec preserve the approved value and compatibility rules. | Keep the Agent-seam `vsn` contract in every applicable form. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Shared authoring errors | Authoring uses structured errors, but final shared codes and callback rules remain pending. | Apply the approved seam-12 contract without changing authoring meaning. | 12 Errors and contracts |
| Release compatibility | Local tests prove the current package set, but publication gates remain broader. | Keep one compatible V3 package matrix and extension contract tests. | 90 Package boundaries, 99 Delivery |

## Approved decisions

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
  [01 Agent](../01_agent/alignment.md). Overview and Agent are approved.
  Package boundaries and errors remain explicit pending assumptions.
- Dependents: 04 Turn evaluation, 05 Plugins, 07 Persistence, 08 Agent Server,
  11 Topology control plane, and 99 Delivery.
- The pending package and error seams are explicit downstream assumptions.
  They do not block the approved authoring contract. A later conflict requires
  a reviewed migration.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
