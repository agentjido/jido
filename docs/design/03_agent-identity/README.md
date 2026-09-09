> Seam review entry point. This document is pending approval.

# 03 — Stable Agent identity

## Briefing

Jido identifies an Agent with separate values at different runtime boundaries.
The Agent value has an ID. A local Registry also uses a Jido instance and a
partition. Persistence adds the Agent module to its key. Live relationships
use IDs, partitions, and PIDs. Jido now provides one public `Jido.Agent.Ref`
with `{namespace, partition, id}`. The Ref stays the same
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
| Agent identity | `%Jido.Agent{}` has one nonempty `id`; `Jido.Agent.Ref` provides the exact portable `{namespace, partition, id}` identity value | Implemented |
| Local runtime | A namespaced instance validates the Ref and resolves the current local PID. Compatible ID and PID functions remain. | Implemented for the local instance boundary |
| Persistence | New namespaced records use a stable Ref key. Agent module and revision remain record data. Compatible legacy keys remain readable under explicit collision rules. | Implemented with no automatic cross-key rewrite |
| Nodes | Remote placement keeps copied IDs, partitions, and PIDs | A node change does not change the Ref |
| Public API | ID-first, PID-first, and Ref-first functions are supported | Keep all supported paths until a separate migration gate |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Downstream Ref use | Value, local lookup, instance lifecycle, and stable storage use are implemented. | Preserve the same Ref in later delivery and placement forms. | 10 Runtime topology |
| Stable namespace | Exact local binding is independent of module and Supervisor names. | Keep namespace separate from location and authority. | 09 complete; 10 and 11 consume it |
| Different identity shapes | Compatible paths still accept term-valued partitions and local handles. | Add new Ref target forms without silently converting legacy partitions. | 10 Runtime topology |
| Storage-key migration | Dual-read and collision detection are implemented. Cross-key rewrite is not atomic in the adapter contract. | Use an offline or provider-owned tool if an application must rewrite legacy keys. | Application or provider owner |
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

- Approved prerequisites: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md), and
  [01 Agent](../01_agent/alignment.md). The approved seam-12 error contract is
  unchanged; its package-boundary inventory revalidation is pending approval.
- Dependents: 07 Persistence, 08 Agent Server, 09 Jido instance,
  10 Runtime topology, and 13 Observability.
- Namespace binding and stable persistence identity are implemented in seam 09.
  Runtime delivery and placement remain with seam 10.

## Documents

- [Target design](design.md)
- [Alignment plan](alignment.md)
