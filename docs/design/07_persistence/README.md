> Implemented seam review entry point. Stable Ref persistence was completed by
> seam 09 on 2026-09-10.

# 07 — Persistence

## Briefing

Jido has one persistence boundary above binary storage adapters.
`Jido.Persistence` owns Agent record meaning, keys, safe encoding, validation,
revisions, logical deletion, checkpoint integration, and storage-result
classification. Adapters own binary `get/2` and exact-byte
`compare_and_swap/4` operations.

Compatible unnamed writes use exact version-2 active or tombstone records. New
namespaced writes use exact version-3 active or tombstone records. A persistent Agent
Server confirms a create-only revision-zero write after Plugin readiness and
before its start call succeeds. Normal delete writes a compact CAS tombstone,
so a delayed writer cannot recreate the deleted record lifetime. Every required
write error stops the current activation.

Default Agent checkpoints run each declared Persistence Plugin facet on only
its paired owned-state value. Complete custom Agent checkpoints bypass that
conversion and keep their opaque callback contract. Legacy outer format-1
active records remain readable.

Unnamed operations keep the compatible instance-and-module key. Namespaced
operations use the complete `{namespace, partition, id}` Ref key. A lone legacy
key remains readable. A legacy and stable key collision fails closed. Jido does
not rewrite across the two keys automatically.

## Owner boundary

- Owner: `Jido.Persistence` and `Jido.Persistence.Adapter`.
- Owns: record format and lifecycle, key derivation, outer identity, state
  revision, safe encoding, logical delete, adapter controls, and classified
  storage results.
- Does not own: Agent checkpoint meaning, Agent Ref fields, Turn evaluation,
  Directive delivery, process placement, discovery, leases, multi-Agent
  transactions, durable workflow history, storage clients, or provider
  maintenance tools.

## Implemented state

| Area | Current contract |
| --- | --- |
| Adapter | Binary get and exact-byte CAS are required. Put and delete are optional maintenance callbacks. |
| Record | Version-2 compatible and version-3 Ref records contain identity, Agent `vsn`, revision, and checkpoint. Tombstones contain identity and revision only. |
| Create | New persistent activation confirms revision zero before the start call succeeds. |
| Commit | Confirmed CAS precedes live replacement and Directives. Every write error removes authority. |
| Delete | Normal delete uses CAS tombstones. Missing delete creates a revision-zero tombstone. |
| Restore | Active records restore. Tombstones return `:deleted`. Corrupt, future, mismatched, and changed-definition records fail closed. |
| Checkpoints | Agent owns default or complete custom maps. Custom maps bypass Plugin slice conversion. |
| Plugins | A Persistence facet converts only the state value owned by its paired Agent facet. |
| Compatibility | Legacy format-1 active records load. Compatible unnamed keys remain. Namespaced operations dual-read and reject a dual-key collision. |
| Backends | ETS, File, and Redis pass one shared get-and-CAS conformance test. |

## Important limits

- An active record does not prove that an Agent process is live.
- CAS is not a lease or cluster ownership protocol.
- Core does not expose normal tombstone purge or same-identity reactivation.
- Redis TTL also applies to tombstones. A TTL limits the duration of the stale-
  writer fence.
- File persistence uses atomic rename for one BEAM. It does not claim file or
  directory sync durability.
- Registry identity reservation uses `:starting`. Public lookup and listing
  expose only `:ready` entries after initial persistence succeeds.
- Cross-key rewrite is not automatic because the adapter cannot atomically
  compare and swap two keys. Downgrade after a version-3 write is unsupported.

## Dependencies

- Implemented prerequisites: package boundaries, errors, Agent checkpoints and
  versions, stable Agent Ref as a value, Turn evaluation, Plugin owner facets,
  and commit authority.
- Active dependents: 08 Agent Server, 09 Jido instance, 10 Runtime topology,
  11 Topology control plane, 13 Observability, and 99 Delivery.

## Documents

- [Selected design](design.md)
- [Implementation evidence](alignment.md)
