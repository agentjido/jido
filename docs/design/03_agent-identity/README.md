> Seam review entry point. This document is pending approval.

# 03 — Stable Agent identity

## Briefing

Jido now identifies an Agent with separate values at different boundaries.
The Agent value has an ID. A local Registry also uses a Jido instance and a
partition. Persistence adds the Agent module to its key. Live relationships
use IDs, partitions, and PIDs. The recommended target adds one public
`Jido.Agent.Ref` with `{namespace, partition, id}`. The Ref stays the same
across process restarts, Jido instance restarts, module changes, and node
changes. Runtime location and write authority stay separate and belong to
later seams.

## Why this seam exists

- Owner: `Jido.Agent.Ref` and the Jido Agent identity boundary.
- Owns: Ref fields, validation, equality, portable encoding, and identity use
  across lookup, persistence, delivery, and placement boundaries.
- Does not own: namespace-to-instance configuration, location discovery,
  placement policy, transport, persistence record layout, or cluster write
  authority.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Agent identity | `%Jido.Agent{}` has one nonempty `id` | One Ref combines namespace, optional partition, and ID |
| Local runtime | Instance Registry keys use partition and ID; callers use ID or PID | Local identity use starts from the Ref; PID stays a replaceable handle |
| Persistence | Keys use instance module, Agent module, partition, and ID | Durable identity is the Ref; modules and revisions are record data |
| Nodes | Remote placement keeps copied IDs, partitions, and PIDs | A node change does not change the Ref |
| Public API | ID-first and PID-first functions are supported | Add Ref-first functions and keep supported APIs during migration |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| No public Ref | Identity has no shared value or round trip | One validated portable Ref contract | 03 Agent identity |
| No stable namespace | Module rename can change storage identity | Stable namespace binding independent of module name | 09 Jido instance |
| Different identity shapes | Lookup, storage, and relationships can disagree | Exact Ref preservation at each boundary | 03, then 07, 08, 09, and 10 |
| Module-based storage key | Code identity and Agent identity are coupled | Staged, collision-safe key migration | 07 Persistence |
| Runtime handles in relationships | A restart can make a saved PID stale | Ref-based public targets with replaceable handles | 08 Agent Server and 10 Runtime topology |
| No location or authority contract | A Ref alone cannot prevent two live writers | Separate location and authority contracts | 10 Runtime topology and later owner seam |

## Decisions requested

1. **Ref model:** Approve `{namespace, partition, id}` with nonempty binary
   strings and `nil` as the default partition.
   Effect: all identity consumers can use one portable value.
2. **Identity exclusions:** Approve that module, definition revision, PID,
   node, activation ID, and storage revision are not Ref fields.
   Effect: code, location, and authority can change without an identity change.
3. **Compatibility:** Approve an additive Ref-first migration. Keep current ID,
   PID, partition, and persistence APIs until owner seams prove each migration.
   Effect: V3 does not remove a supported API in this seam.
4. **Later ownership:** Approve that this seam does not select placement,
   location discovery, transport, or cluster authority.
   Effect: later seams can use the Ref without receiving policy from this seam.

## Dependencies

- Prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), and
  [01 Agent](../01_agent/alignment.md). All are pending drafts.
- Dependents: 07 Persistence, 08 Agent Server, 09 Jido instance,
  10 Runtime topology, and 13 Observability.
- Blockers: prerequisite approval, namespace binding rules, partition
  migration, and persistence-key migration.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
