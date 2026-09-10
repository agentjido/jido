> Implemented seam alignment. This document records the selected contract and
> its evidence.

# Topology control-plane alignment

## Status

- Design selected and implemented: 2026-09-10.
- Alignment state: `Implemented` for the Jido core seam.
- Compatibility state: V3-only. Topology DSL sections now have one canonical
  location, and the Codec reads only the current version-2 document.
- External state: distributed control-plane functions are deferred to an
  application or focused integration package. They do not block Jido V3 core.
- Follow-on work: seam 12 owns the final error inventory, seam 13 owns public
  observation, and seam 99 owns the full delivery gate.

## Selected contract

Jido core is one Topology component. Static authoring validates a source
definition. Pure instance planning validates input, asks declared Topology
Plugin facets for static entries, and builds one stable plan. These steps
start no Jido process.

The module DSL has one root shape. `agent` defines an optional control Agent.
`routes` uses the normal Agent DSL and requires `agent`. `topology` contains all
topology-specific sections. The control Agent and topology are independently
optional, and neither starts the other.

Contribution uses this fixed order:

1. Root and included Topologies expand in their own scopes.
2. Each scope processes Agent declarations in source order.
3. Each scope then processes group declarations in source order.
4. Each declaration processes Plugin packages in declaration order.
5. Jido appends all entries after explicit source entries.
6. Common definition and graph validation checks the complete result.

A Topology facet can contribute current Bus resources, ownership relationships,
and Bus subscriptions. It cannot add an Agent, add a new resource kind, start a
runtime, persist state, or grant authority. Each group declaration gets one
contribution. Its expanded members use the resulting group relationships and
subscriptions.

The `%Jido.Topology.Instance{}` keeps the validated source definition. The
expanded entries live in its Plan. `Jido.Topology.Plan.build/3` and
`Jido.Topology.instantiate/2` produce the same expanded plan for the same
definition, ID, and input.

One `Jido.Topology.Controller` activates one current instance for one Jido
instance. The application supervises it beside the Jido instance. It owns
dependency order, bounded startup, readiness, repair, additive Agent updates,
exact known-node placement, lifecycle Signals, and cleanup. `reconcile/2`
repairs the current target. `update/3`
accepts only a validated target that keeps every existing Agent and resource
specification unchanged.

An Agent or group declaration can contain an exact `node:` value. The
Controller node is the default. `place_agent/4` changes one effective node after
it confirms and stops the old Agent. The Controller does not select a node and
does not fall back to local activation. A remote Agent cannot use a
Controller-owned local Bus.

The optional `:lifecycle` target is an Agent PID or Ref. The Controller sends
bounded `jido.topology.lifecycle.**` Signals for operations, component results,
and status changes. Delivery is best effort and cannot change runtime results.

## Four-module Plugin seam

| Module | Input owned by this seam | Output used by this seam | Live authority |
| --- | --- | --- | --- |
| `Jido.Agent.Plugin` | Agent declaration and state schema | None during Topology planning | None |
| `Jido.AgentServer.Plugin` | Live activation context | None during Topology planning | Only its bounded live facet callbacks |
| `Jido.Persistence.Plugin` | One paired owned state value | None during Topology planning | None |
| `Jido.Topology.Plugin` | Package, version, Agent key and module, static options | Canonical Bus, ownership, and subscription entries | None |

The package manifest selects the facets. The contribution dispatcher invokes
only the Topology facet. Normal Agent definition validation still validates the
complete package declaration. A contribution does not start a Server runtime
or run a Persistence conversion.

## Distributed boundary

Jido core does not implement cluster membership, discovery, placement
selection, rebalance policy, handoff, automatic failover, leases, authority epochs,
network-partition policy, or operator control actions.

An external control plane can use these public inputs:

- a complete Agent Ref for stable identity;
- explicit Jido activation and lifecycle calls;
- local Ref resolution and current status calls;
- the durable per-Agent record contract;
- explicit caller-selected known-node child placement.
- exact known-node Topology placement after policy has selected a node.
- bounded lifecycle Signals delivered to a normal control Agent route.

The external owner must keep desired placement, current location, and write
authority as separate values. Membership is placement input only. A Registry
entry, a PID, a known node, and persistence compare-and-swap are not authority
grants. Any exclusive-owner or safe automatic-failover claim requires a newer
authority epoch that every protected commit can enforce.

Requirements `TOP-REQ-006` through `TOP-REQ-058`, and `TOP-REQ-061`, are the
reference contract for such an external package. They are not implemented by
Jido core and are not core release blockers.

## Canonical implementation

| Contract | Source |
| --- | --- |
| Static definition and instance boundary | `Jido.Topology` |
| Recursive contribution order and common validation | `Jido.Topology.Plugin.expand_definition/1` |
| Owner-bounded facet call and context | `Jido.Topology.Plugin` |
| Canonical contribution value | `Jido.Topology.Plugin.Contribution` |
| Direct plan parity | `Jido.Topology.Plan.build/3` |
| Included-scope addresses and graph validation | `Jido.Topology.Composition` |
| Activation, repair, additive Agent update, placement, and lifecycle Signals | `Jido.Topology.Controller`, `Jido.Topology.Controller.Runtime`, and the custom modules under `Jido.Topology.Signal` |
| Public local Agent lifecycle and Ref operations | `Jido` and `Jido.Instance.RefFacade` |
| Durable per-Agent restore | `Jido.Persistence` and `Jido.Topology.Controller.Activation` |

## Evidence matrix

| Requirement group | Evidence | State |
| --- | --- | --- |
| `TOP-REQ-001` to `TOP-REQ-005` | Topology validation, composition, Controller, core-scope, and package-boundary evidence | `Proven` for the selected local and external-owner boundary |
| `TOP-REQ-006` to `TOP-REQ-058` | No Jido core implementation is selected | `Deferred external reference contract` |
| `TOP-REQ-059`, `TOP-REQ-060` | Existing Topology and Controller suites plus fixed-target API text | `Proven` |
| `TOP-REQ-061` | No external control-plane protocol is selected | `Deferred with its external owner` |
| `TOP-REQ-062` | Authoring-host, Plugin, Controller, and runtime-topology evidence | `Proven` |
| `TOP-REQ-063` to `TOP-REQ-068` | Plugin integration unit and executable example tests | `Proven` |
| `TOP-REQ-069` to `TOP-REQ-076` | Controller update unit tests and UP-07 research example | `Proven` |
| `TOP-REQ-077` to `TOP-REQ-099` | Authoring, Codec, Controller, placement peer, lifecycle, and example tests | `Proven` |

## Executable evidence

| Evidence | Behavior proved |
| --- | --- |
| `test/jido/topology/plugin_integration_test.exs` | Explicit entries stay first. Agent, group, and Plugin order is stable. Bus, subscription, and ownership entries enter the common graph. Source definitions stay unchanged. Direct planning matches instantiation. Included contributions stay in their component scope. A duplicate contribution fails before activation. |
| `test/examples/07_topology/07_06_plugin_contribution` | A Topology-only Plugin package contributes a Bus and subscription. The Controller starts them, and a published Signal reaches the Agent. |
| `test/jido/topology` | Authoring, validation, composition, input, group, Controller, readiness, repair, restore, conflict, and cleanup behavior stays valid. |
| `test/examples/07_topology` | All documented systems run through the same Controller, lifecycle Signal, and Plugin policy contracts. |
| `test/jido/topology/controller_placement_test.exs` | Exact placement starts and moves one Agent across two connected Erlang nodes. |
| `test/jido/topology/controller_update_test.exs` | Additive targets retain existing PIDs and state, become the later repair target, and reject removals or changed definitions. |
| `test/examples/99_research/99_16_topology_upgrade` | UP-07 grows a live worker group with no skip and retains unchanged Agent PIDs and state. |
| Distributed child and authority tests | Known-node placement works as a bounded primitive. The exclusive-owner case remains an explicit non-guarantee. |

## Compatibility decisions

| Area | Decision |
| --- | --- |
| Static authoring | Keep module DSL, direct values, Builder, Codec version 2, composition, and authoring extensions. Use only the root `agent`, `routes`, and `topology` shape. |
| Source definition | Keep it free of generated contribution entries. Store expansion only in the Plan. |
| Plugin declarations | Keep module and `{module, options}` forms and their order. |
| Plan | Add Topology facet expansion to normal instance and direct Plan construction. |
| Owner helpers | Keep `owner/0` and `new_agent/1` as authoring helpers only. |
| Controller | Keep application supervision, readiness, repair modes, status, lookup, additive Agent update, lifecycle Signals, and exact node placement. |
| Repair and update | Keep `reconcile/2` as current-target repair. Use `update/3` only for additive Agents. Controller replacement remains required for removal, replacement, or resource changes. |
| Persistence | Keep independent per-Agent records. Add no desired-placement or authority data to Agent checkpoints. |
| Remote placement | Keep explicit caller-selected known-node placement and no local fallback. |
| Cluster features | Add no core membership, discovery, automatic placement, failover, lease, fence, or exclusive-owner claim. |

## Limits

- Topology Plugin code is application code. The contract requires it to be
  pure, but Elixir cannot prevent arbitrary side effects inside a callback.
- Contribution runs each time Jido builds or verifies an instance plan. It must
  be deterministic for fixed definition data.
- Explicit source graph references must be valid before contribution. A facet
  must contribute any connection that depends on its contributed resource.
- Two contributions cannot declare the same key or duplicate the same
  subscription. The common validator rejects the complete plan.
- The Controller can grow a group when existing Agent and resource
  specifications stay unchanged. It can move one Agent to an exact node. It
  does not remove a member, change resources, or select placement policy.
- A Controller marker prevents unrelated local takeover only. It does not
  fence another Erlang node.
- Persistent restore does not provide distributed desired-state storage or an
  authority grant.

## Verification record

Topology verification passed on 2026-09-10:

```text
mix test test/jido/topology --exclude peer --seed 0

106 passed, 1 excluded

mix test test/examples/07_topology --include example --seed 0

9 passed

mix test test/jido/topology/controller_placement_test.exs --only peer --seed 0

1 passed

mix test --seed 0

1002 passed, 271 excluded

mix test.livebooks

21 passed

mix docs --warnings-as-errors

documentation generated with no warnings

mix dialyzer

no errors
```

Formatting and the diff check also passed.

## Completion criteria

- [x] Static definitions and plans remain process-free Jido values.
- [x] Topology Plugin facets are called by the Topology owner during planning.
- [x] Contribution order is deterministic and documented.
- [x] Included Topologies receive contributions in their own scopes.
- [x] Common validation checks the complete contributed graph before
      activation.
- [x] The source definition stays unchanged and direct Plan construction has
      parity with instantiation.
- [x] The executable example proves a contributed Bus and subscription.
- [x] The four Plugin owner modules keep separate authority.
- [x] The Controller keeps same-target repair and accepts only additive Agent
      target updates.
- [x] Authoring owner helpers have no implicit runtime authority.
- [x] Distributed control-plane policy stays outside Jido core.
- [x] External distributed requirements are explicit non-core reference
      requirements, not unresolved core blockers.
