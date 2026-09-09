> Implemented seam alignment. This document records the selected contract and
> its evidence.

# Topology control-plane alignment

## Status

- Design selected and implemented: 2026-09-09.
- Alignment state: `Implemented` for the Jido core seam.
- Compatibility state: additive. Existing Topology, Builder, Codec, Plan,
  Controller, repair, readiness, and lookup behavior stays supported.
- External state: distributed control-plane functions are deferred to an
  application or focused integration package. They do not block Jido V3 core.
- Follow-on work: seam 12 owns the final error inventory, seam 13 owns public
  observation, and seam 99 owns the full delivery gate.

## Selected contract

Jido core is one local Topology component. Static authoring validates a source
definition. Pure instance planning validates input, asks declared Topology
Plugin facets for static entries, and builds one stable local plan. These steps
start no Jido process.

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

One `Jido.Topology.Controller` activates one fixed instance on one local Jido
instance. The application supervises it beside the Jido instance. It owns
dependency order, bounded startup, readiness, local repair, and cleanup.
`reconcile/2` repairs the same target. It does not replace that target.

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

Jido core does not implement cluster membership, discovery, automatic
placement, rebalance, handoff, automatic failover, leases, authority epochs,
network-partition policy, or operator control actions.

An external control plane can use these public inputs:

- a complete Agent Ref for stable identity;
- explicit Jido activation and lifecycle calls;
- local Ref resolution and current status calls;
- the durable per-Agent record contract;
- explicit caller-selected known-node child placement.

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
| Fixed-target local activation and repair | `Jido.Topology.Controller` and `Jido.Topology.Controller.Runtime` |
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

## Executable evidence

| Evidence | Behavior proved |
| --- | --- |
| `test/jido/topology/plugin_integration_test.exs` | Explicit entries stay first. Agent, group, and Plugin order is stable. Bus, subscription, and ownership entries enter the common graph. Source definitions stay unchanged. Direct planning matches instantiation. Included contributions stay in their component scope. A duplicate contribution fails before activation. |
| `test/examples/07_topology/07_06_plugin_contribution` | A Topology-only Plugin package contributes a Bus and subscription. The Controller starts them, and a published Signal reaches the Agent. |
| `test/jido/topology` | Authoring, validation, composition, input, group, Controller, readiness, repair, restore, conflict, and cleanup behavior stays valid. |
| `test/examples/07_topology` | All documented local systems run through the same Controller contract. |
| Distributed child and authority tests | Known-node placement works as a bounded primitive. The exclusive-owner case remains an explicit non-guarantee. |

## Compatibility decisions

| Area | Decision |
| --- | --- |
| Static authoring | Keep module DSL, direct values, Builder, Codec versions 1 and 2, composition, and authoring extensions. |
| Source definition | Keep it free of generated contribution entries. Store expansion only in the Plan. |
| Plugin declarations | Keep module and `{module, options}` forms and their order. |
| Plan | Add Topology facet expansion to normal instance and direct Plan construction. |
| Owner helpers | Keep `owner/0` and `new_agent/1` as authoring helpers only. |
| Controller | Keep application supervision, fixed target, readiness, repair modes, status, and lookup. |
| Repair | Keep `reconcile/2` as same-target repair. A live update needs a separate contract. |
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
- The Controller does not resize groups or replace a definition.
- A Controller marker prevents unrelated local takeover only. It does not
  fence another Erlang node.
- Persistent restore does not provide distributed desired-state storage or an
  authority grant.

## Verification record

Verification passed on 2026-09-09:

```text
mix test test/jido/topology test/jido/plugin/facets_test.exs --seed 0

106 passed

mix test test/examples/07_topology --only example --seed 0

7 passed

mix test test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs \
  --include example --seed 0

4 passed, 1 skipped

mix test test/jido/agent_server/distributed_child_test.exs \
  test/jido/agent_server/remote_lifecycle_test.exs \
  test/jido/agent_server/distributed_authority_test.exs \
  --include research --seed 0

19 passed, 1 skipped

mix quality

1181 passed, 1 excluded

mix docs --warnings-as-errors

documentation generated with no warnings
```

The Topology-upgrade skip is the deferred live-target update contract. The
distributed-authority skip is the explicit non-guarantee for exclusive cluster
ownership. The quality exclusion is the same approved external-provider case.
The diff check also passed.

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
- [x] The local Controller keeps one fixed target and same-target repair.
- [x] Authoring owner helpers have no implicit runtime authority.
- [x] Distributed control-plane policy stays outside Jido core.
- [x] External distributed requirements are explicit non-core reference
      requirements, not unresolved core blockers.
