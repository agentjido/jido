# Compatibility register

This register applies to the Jido `3.0.0-beta.1` core candidate and the package
matrix in this folder.

## Support interval

The public V3 surfaces in this candidate remain available through the `3.0.x`
line. A removal needs an approved owner-seam migration, replacement tests,
release notes, and a later major-version gate. This candidate has no deprecated
or removed V3 API.

## Public changes

| Area | Status | Compatibility rule |
| --- | --- | --- |
| Four Plugin facets | Added | Use `Jido.Agent.Plugin`, `Jido.AgentServer.Plugin`, `Jido.Persistence.Plugin`, and `Jido.Topology.Plugin`. One `Jido.Plugin` package composes them. |
| Agent Ref and instance facade | Added | Ref-first functions exist beside supported ID, PID, name, and partition functions. |
| Turn routing | Changed from an earlier beta | The first target in Router order wins. Selection uses the unchanged source Signal before Plugin preparation. |
| Durable records | Added and versioned | Compatible unnamed keys use outer format 2. Namespaced Ref keys use outer format 3. Supported V3 outer format-1 active records remain readable. |
| Agent Server activation | Strengthened | Initial durable creation completes before public readiness. A required write error removes write authority and stops the activation. |
| Topology Plugin planning | Added | Contributions are pure plan input. They cannot start processes, persist state, or grant authority. |
| Semantic observation | Added | Version-1 events and bounded metadata exist beside legacy observation paths. |
| Existing V3 public APIs | Retained | No removal or deprecation is approved. |

## Stored data and rollback

- Jido does not read V2 storage records automatically.
- A V2 import must run old-code decoding, application conversion, and a new V3
  write. V2 and V3 writers must use separate keys.
- A lone compatible V3 key can be read. A simultaneous compatible and stable
  key for one Ref fails closed. Jido does not move data across keys automatically.
- Older code cannot read a namespaced format-3 record. Downgrade after the first
  such write is unsupported. Restore a pre-cutover backup and reconcile external
  work if rollback is needed.
- A failed state commit keeps the prior committed Agent state. Jido cannot undo
  external I/O that an Action or Flow completed before that failure.

## Unsupported transitions

This candidate does not claim active-Turn code revision pinning, live Agent
definition migration, live Topology target replacement, cluster-exclusive
ownership, automatic failover, or a built-in OpenTelemetry bridge. The
[scope ledger](scope-ledger.md) gives each item an owner and review point.
