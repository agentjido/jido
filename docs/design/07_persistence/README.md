> Seam review entry point. This document is pending approval.

# 07 — Persistence

## Briefing

Jido has a working persistence core. `Jido.Persistence` owns Agent record
meaning, encoding, identity checks, revisions, checkpoint calls, restore calls,
and adapter fault containment. ETS, File, and Redis adapters store binary keys
and values and provide atomic compare-and-swap (CAS). A live commit writes
before it changes the authoritative Agent or starts Directives. The recommended
target keeps this byte boundary. It adds an initial revision-zero record before
readiness, a CAS tombstone for logical deletion, a closed CAS result set, and
one write-authority rule. It also defines safe migration for stable Agent Ref,
definition revision, record format, custom checkpoints, and Plugin-owned state.

Code remains the source of truth for current behavior. All target requirements
and decisions are pending approval.

## Why this seam exists

- Owner: `Jido.Persistence` and `Jido.Persistence.Adapter`.
- Owns: durable Agent record meaning, binary key derivation, record encoding and
  validation, record revisions, logical deletion, adapter controls, and the
  storage result passed to the commit boundary.
- Does not own: Agent checkpoint meaning, Agent Ref fields, candidate creation,
  Directive delivery, Agent Server process policy, storage clients, discovery,
  cluster ownership, multi-Agent transactions, or durable workflow history.

## Current and target state

| Area | Current | Recommended target |
| --- | --- | --- |
| Storage boundary | Adapters implement binary `get`, `put`, CAS, and `delete`. | Keep binary `get` and CAS as the required runtime contract. Keep current maintenance operations during migration. |
| Record | A private format-1 active-record map includes instance module, Agent module, partition, ID, revision, and checkpoint. | Use a versioned active-or-tombstone record. Keep code identity and revision outside Agent Ref. |
| Identity | The key includes instance module, Agent module, partition, and ID. | Use the complete stable Agent Ref after a collision-safe, dual-read migration. |
| Creation | A new persistent Server can become ready before any record exists. | Confirm a create-only revision-zero CAS before readiness. |
| Commit | Exact-byte CAS precedes live replacement and Directives. | Keep this order and classify every non-confirmed write result. |
| Delete | A blind delete removes revision history. | Write a CAS tombstone. Keep physical purge outside normal Agent lifecycle. |
| Restore | Active records restore; corrupt and mismatched data fail. | Keep fail-closed restore, add tombstone and definition-revision checks, and preserve legacy reads during migration. |
| Checkpoints | Agents own default or custom plain-map checkpoints. | Keep complete custom callbacks. Keep outer record validation and explicit format compatibility. |
| Plugins | Plugin state is in the complete Agent checkpoint. | Permit only pure owned-slice conversion after its Plugin contract is approved. |
| Backends | ETS, File, and Redis exist. | Keep them. Defer Ecto and Bedrock placement until the core contract and package owner are approved. |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No initial record | Initial state can be lost after readiness. | Revision-zero create before publication. | 07 Persistence, 08 Agent Server |
| Blind deletion | A delayed writer can recreate a deleted identity. | CAS tombstone with retention, purge, and reactivation rules. | 07 Persistence |
| Mixed write failure policy | A conflict can leave a stale Server active. | One authority-loss rule for all required write failures. | 06 Commit, 07 Persistence, 08 Agent Server |
| Identity and format migration | Module-based keys conflict with stable Ref. | Collision-safe legacy reads, new writes, rollback, and removal gates. | 03 Agent identity, 07 Persistence, 09 Jido instance |
| Checkpoint evolution | Definition and Plugin migrations are not complete. | Compatible default, custom, and owned-slice rules. | 01 Agent, 05 Plugins, 07 Persistence |
| Adapter proof | Current adapters have separate test sets. | One conformance suite and backend-specific durability evidence. | 07 Persistence, adapter owners |

## Decisions requested

1. **Boundary:** Keep `Jido.Persistence` above a binary adapter. Do not add
   record-valued instance persistence callbacks.
2. **Adapter surface:** Make `get/2` and `compare_and_swap/4` the required
   runtime operations. Keep `put/3` and `delete/2` only as compatible
   maintenance APIs until a separate deprecation decision.
3. **Record lifecycle:** Use active records and compact tombstones. Do not add
   a durable `:hibernated` state.
4. **Creation:** Require a create-only revision-zero write before a new
   persistent activation reports ready, including `restore: false`.
5. **Write authority:** Remove write authority after every required write
   error, including a confirmed conflict.
6. **Identity migration:** Adopt Ref-based keys only after namespace, partition
   conversion, collision, dual-read, and rollback rules are approved.
7. **Serialization:** Keep Agent-owned plain-map checkpoints and a
   Persistence-owned outer record. Read legacy format 1 during migration.
8. **Custom checkpoints and Plugins:** Keep complete custom callbacks. Bypass
   Plugin slice conversion for them in the first stage.
9. **Providers:** Keep ETS, File, and Redis. Defer Ecto and Bedrock placement
   and release claims until conformance and package decisions are complete.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md),
  [01 Agent](../01_agent/alignment.md),
  [03 Agent identity](../03_agent-identity/alignment.md),
  [04 Turn evaluation](../04_turn-evaluation/alignment.md),
  [05 Plugins](../05_plugins/alignment.md), and
  [06 Commit and effects](../06_commit-and-effects/alignment.md). All are
  pending drafts.
- Related input: [02 Agent authoring](../02_agent-authoring/design.md) defines
  serialization separation and definition-revision propagation.
- Dependents: 08 Agent Server, 09 Jido instance, 10 Runtime topology, 11
  Topology control plane, 13 Observability, and 99 Delivery.
- Blockers: prerequisite approval, stable namespace and partition conversion,
  final write-authority policy, mixed record versions, tombstone retention and
  purge, custom-checkpoint composition, and production adapter placement.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
