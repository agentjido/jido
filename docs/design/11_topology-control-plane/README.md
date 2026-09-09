> Implemented seam review entry point.

# 11 - Topology control plane

## Briefing

Jido core owns static local Topology planning and fixed-target repair. It does
not own a distributed control plane.

During pure instance planning, the Topology owner now asks each declared
`Jido.Topology.Plugin` facet for static entries. The four-module Plugin seam is
complete:

| Owner module | Topology role |
| --- | --- |
| `Jido.Agent.Plugin` | Defines pure Agent preparation and owned state. |
| `Jido.AgentServer.Plugin` | Defines live callbacks and an optional runtime root. |
| `Jido.Persistence.Plugin` | Converts one owned state value for a record. |
| `Jido.Topology.Plugin` | Contributes static Bus, ownership, and subscription entries to planning. |

Jido applies Agent contributions first, then group contributions. Each
declaration keeps Plugin declaration order. Included Topologies receive the
same expansion in their own scope. The common validator checks the complete
graph before activation. The source definition stays unchanged.

One application-supervised `Jido.Topology.Controller` starts and repairs one
fixed `%Jido.Topology.Instance{}` on one Jido instance. `reconcile/2` repairs
that target. It does not resize, update, move, rebalance, hand off, or recover
an Agent on another node.

## Owned contract

- Topology definition and instance construction start no Jido process.
- Topology Plugin contribution is pure static planning work.
- A contribution can add current Bus resources, ownership relationships, and
  Bus subscriptions. It cannot add Agents or a new resource kind.
- Duplicate keys, unknown endpoints, duplicate subscriptions, and graph cycles
  fail before Controller activation.
- A group receives one contribution for its declaration. All expanded members
  receive the resulting group connection.
- The Controller owns local dependency order, readiness, repair, and cleanup.
- A Controller target is fixed for its lifetime.
- Authoring owner helpers and Plugin facets have no implicit runtime or
  distributed authority.

## Distributed boundary

Membership, discovery, automatic placement, rebalance, handoff, automatic
failover, leases, fencing, network-partition policy, and operator controls stay
outside Jido core. An application or focused integration can build those
functions with public Jido activation, Ref, persistence, and inspection
contracts.

A known Erlang node is a caller-selected location. It is not discovery or
write authority. A Registry entry and persistence compare-and-swap are also not
authority grants. A system must enforce a newer authority epoch at every
protected commit before it can claim exclusive ownership or safe automatic
failover.

The detailed provider, placement, recovery, and operator requirements in the
design are an external reference contract. They are not Jido core V3 release
requirements.

## Evidence

- `test/jido/topology/plugin_integration_test.exs` proves ordered Agent and
  group contribution, source-definition preservation, direct-plan parity,
  included-scope expansion, and conflict rejection.
- `test/examples/07_topology/07_06_plugin_contribution` proves that a
  contributed Bus and subscription work through the local Controller.
- The existing Topology suites prove authoring, composition, stable local
  plans, readiness, repair, restore, conflict handling, and cleanup.
- The runtime-topology and distributed-child suites prove that explicit
  known-node activation is the lowest remote primitive and has no fallback or
  exclusive-owner guarantee.

## Follow-on seams

- 12 Errors and contracts owns the final public error inventory.
- 13 Observability owns public semantic events and bounded status projections.
- 99 Delivery owns the full cross-package and release gate.
- An external package owns any later distributed control plane.

## Documents

- [Selected design](design.md)
- [Implemented alignment and evidence](alignment.md)
