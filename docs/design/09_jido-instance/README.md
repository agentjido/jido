> Implemented seam review entry point.

# 09 - Jido instance

## Briefing

A Jido instance is the application-owned local runtime boundary. It is a
standard OTP Supervisor, owns five local runtime services, starts Agent
Servers, and provides lifecycle helpers.

The implemented seam adds an optional stable namespace and a Ref-first facade.
It keeps all current ID, PID, partition, generated instance, and public Agent
Server APIs. It does not make the instance a global runtime, transport router,
placement service, or topology control plane.

## Owned contract

- `Jido.Instance.Options` validates the complete final instance configuration
  before child startup.
- `Jido.Instance.NamespaceRegistry` gives each exact namespace one live local
  binding. Its binding table survives a registry worker restart.
- `Jido.Instance.RefFacade` validates a complete Ref, checks the instance
  namespace, resolves the current local Server, and delegates through public
  Agent Server functions.
- `Jido.Persistence` uses stable namespaced keys and record format 3 for new
  namespaced records.
- Legacy and stable persistence keys have explicit dual-read and collision
  rules. Jido does not do an unsafe automatic cross-key rewrite.

## Boundaries

The seam owns local instance startup, local service names, final instance
configuration, namespace binding, local Ref resolution, facade policy, and the
instance persistence default.

It does not own Agent or Turn semantics, Plugin callbacks, persistence adapter
operations, Signal routing, transport, cluster authority, Topology
definitions, or topology control.

## State

| Area | Implemented state |
| --- | --- |
| Runtime role | One application-owned `:one_for_one` Supervisor with five standard local services. |
| Configuration | Final keyword validation after application config and runtime options merge. |
| Identity | Optional nonempty namespace, separate from local module, process, and node identity. |
| Ref facade | Additive identity, publication, command, control, lifecycle, and inspection functions. |
| Persistence | Stable `{namespace, partition, id}` key for namespaced records, with honest legacy collision handling. |
| Compatibility | Existing ID, PID, partition, hibernate, thaw, debug, and direct Server paths remain supported. |
| Scope | Local resolution only. No implicit transport or Controller fallback. |

## Follow-on seams

- 10 Runtime topology owns any split between Agent and Plugin runtime pools.
- 11 Topology control plane consumes Ref-first local activation but does not
  gain write authority from the namespace.
- 12 Errors and contracts owns broader compatibility-result normalization.
- 13 Observability owns later status and event projections.

## Documents

- [Selected design](design.md)
- [Implemented alignment and evidence](alignment.md)
