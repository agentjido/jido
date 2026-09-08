> Seam review entry point. This document is pending approval.

# 00 — Core model, shared terms, and invariants

## Briefing

The recommended V3 architecture keeps the implemented local runtime as its
base. It keeps immutable Agent values, direct evaluation, one Agent Server
commit point, Builder, Codec, owned children, public PID APIs, persistence
adapters, static local Topology, and current observation paths. The main target
changes are source-Signal route selection, isolated Plugin inputs, stable Agent
identity, definition revision, stronger durable lifecycle rules, and coherent
Plugin runtime replacement. This seam defines only the shared model and
invariants. Each owner seam defines its detailed API.

The [design review index](../README.md#document-review-status) is the source of
truth for approval. It has no `Approved` Overview entry. Thus, no
recommendation or target requirement in this folder is an approved decision.

## Why this seam exists

- Owner: the shared Jido Agent model and cross-system boundaries.
- Owns: common terms, the Agent-to-Turn-to-commit model, the Jido and OTP
  boundary, cross-system invariants, owner-seam assignments, and dependency
  gates.
- Does not own: detailed structs, callback signatures, error codes, storage
  operations, supervision layouts, or topology update protocols.

## Current and target state

| Area | Canonical current state | Recommended target |
| --- | --- | --- |
| Turn selection | Plugins can change a Signal before routing. Jido requires exactly one route match. | Preserve the source Signal. Select the first Router match before Plugin preparation. Fix that executable for the Turn. |
| Evaluation | Direct and live commands share the private Runner. | Keep one candidate-evaluation boundary. Only the live Agent Server commits. |
| State ownership | An executable writes domain state. Each stateful Plugin can replace one owned state entry. Plugins can read the complete Agent during preparation. | Keep separate write owners. Give each Plugin only its declared Agent view, owned input, and owned Directives. |
| Commit and effects | One successful live Turn increments `state_version` once. Directive work starts after commit. Action and Flow I/O can occur before commit. | Keep one commit point. Do not claim rollback for pre-commit external I/O. |
| Identity and restore | Registry and persistence use different identity inputs. A PID is the public live handle. Checkpoints have no definition revision. | Add stable Agent Ref and definition revision through compatible stages. Keep current ID and PID APIs during migration. |
| Durability | Compare-and-swap records are private maps. Persistent startup writes no initial record. Some confirmed write failures can leave a Server active. Delete removes the record. | Add an initial active record, remove write authority after every write error, and use a compare-and-swap tombstone for normal deletion. |
| Runtime recovery | A named instance restores the last nondurable runtime checkpoint after an abnormal nonpersistent Server restart. Plugin replacement pulls current state after start. | Keep runtime-checkpoint restore. Start each replacement Plugin runtime with matching committed Plugin state and state version. |
| Topology and observation | Static local Topology, manual repair, semantic telemetry, legacy telemetry, tracing, and debug paths exist. | Keep static local Topology and supported observation APIs. Defer live topology control and any removal until owner seams define migration and proof. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Route and Plugin input contract | Current preparation can change selection and expose the complete Agent. | One fixed executable from the source Signal and isolated Plugin-owned inputs. | 01 Agent, 04 Turn evaluation, 05 Plugins |
| Stable identity and definition revision | Current location, storage key, and definition meaning do not use one durable contract. | Stable Ref semantics and restore checks with a staged compatibility path. | 01, 02, 03, 04, 07, 09, 10 |
| Durable lifecycle | Current creation, write-error, and delete rules do not give one safe record lifecycle. | Initial active records, loss of write authority, and tombstone semantics. | 06 Commit and effects, 07 Persistence, 08 Agent Server, 10 Runtime topology |
| Plugin ownership and replacement | Current Plugin behavior mixes pure and live work, and replacement input is not one coherent snapshot. | Owner-specific Plugin boundaries and state-version-coherent replacement. | 05, 08, 09, 10 |
| Public values and errors | Several proposed structs do not exist, and current public protocols use structs, maps, tuples, and atoms. | One owner and migration rule for each public value and error. | 12 Errors and contracts, 90 Package boundaries, value owners |
| Acceptance coverage | Skipped research tests specify several target contracts but do not prove them. | Passing owner-seam evidence for each approved Overview requirement. | All dependent seams, closed by 99 Delivery |

## Decisions requested

These are recommended decisions. They are not approved.

1. **Route contract:** Select the first Router match from the source Signal
   before Plugin preparation. Admission and preparation cannot replace it.
2. **Nonpersistent restart:** Keep the current last-commit runtime checkpoint
   rule for abnormal restart in the same Jido instance.
3. **Stable identity:** Make Agent Ref a V3 target and keep current ID and PID
   APIs during migration.
4. **Definition revision:** Use a positive module-owned revision, preserve it
   in all authoring forms, and define a rule for old checkpoints.
5. **Plugin ownership:** Use Agent, Agent Server, Persistence, and Topology as
   the four proposed facet owners under one ordered Plugin declaration.
6. **Custom checkpoints:** Keep complete Agent `checkpoint/2` and `restore/2`
   callbacks until their composition with Persistence facets is explicit.
7. **Durability scope:** Require initial active records, loss of write authority
   after every write error, and tombstones for V3.
8. **Compatibility APIs:** Keep DSL and direct authoring, Builder, Codec,
   neutral definitions, custom routing, owned children, public PID APIs, and
   local debug paths for the V3 release.
9. **Topology scope:** Keep static local activation and repair. Defer owner-Agent
   live control and live target updates.
10. **Package boundary:** Keep Jido core local. Keep general durable, cluster,
    and transport services outside core.
11. **Public values:** Approve value roles only. Let seam 12, seam 90, and each
    value owner decide exact shapes and migration.
12. **Observation:** Make semantic Agent events the target. Keep legacy
    telemetry, `Jido.Observe`, and debug paths during migration.

## Dependencies

- Prerequisites: None. This is the first alignment gate.
- Dependents: 90, 12, 01 through 11, 13, and 99, in the order in
  `docs/design/AGENTS.md`.
- Blockers: The 12 decisions above are pending approval. Detailed dependent
  seams cannot treat them as approved contracts.
- Lower layers: `jido_action` owns executable work. `jido_signal` owns the
  Signal envelope and ordered route matching. Jido owns how these contracts
  become one Agent Turn.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
