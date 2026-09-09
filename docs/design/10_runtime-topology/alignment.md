> Implemented seam alignment. This document records the selected contract and
> its evidence.

# Runtime topology alignment

## Status

- Design selected and implemented: 2026-09-09.
- Alignment state: `Implemented`.
- Compatibility state: additive. Existing instance, Agent Server, Plugin,
  child, and explicit known-node APIs remain supported.
- Follow-on work: seam 11 owns desired state and repair. Seam 13 owns public
  observation projections. Seam 99 owns final delivery.

## Selected contract

One Jido instance is one local component runtime. It starts five direct
children in this order:

1. Task Supervisor.
2. unique-key Registry.
3. Runtime Store.
4. Spawn Registry.
5. Agent Dynamic Supervisor.

The instance uses `:one_for_one`. Each service has an instance-local name.
`max_tasks` applies only to the Task Supervisor. Controlled replacement of one
standard child does not replace a sibling.

Agent Servers are direct peer children of the Agent Dynamic Supervisor. They
do not nest under logical Agent parents. A managed Server uses `:transient` by
default. A directly linked Server uses `:temporary` by default.

The current Plugin placement also uses the Agent Dynamic Supervisor. Each
Plugin runtime wrapper is temporary and linked to its Agent Server. It owns a
private Supervisor and one runtime generation. Plugin authors must return a
root specification with `restart: :permanent`. The wrapper changes the hosted
generation to `:temporary`. This lets the wrapper observe root loss, request a
fresh committed Plugin state and Agent state version, and start the new
generation. The wrapper, the private Supervisor, and the root stop with the
Agent Server.

Admission, execution, Plugin Directive, and error Signal delivery workers use
the selected instance Task Supervisor. Initial Plugin readiness is linked and
monitored by the Agent Server. Replacement readiness is linked and monitored
by the Plugin wrapper. Controlled and abrupt owner death stops each owned
worker.

The Runtime Store owns nondurable coordination data for one live instance
generation. Its ETS table survives a Runtime Store worker restart because the
instance Supervisor owns the table. A full instance stop removes the table.
The new generation starts with no runtime checkpoints or spawn receipts.
Durable records remain in their adapter, but the instance does not discover or
start them. An explicit child specification, `thaw`, Ref activation, or a
Controller decision must activate them.

Logical child records and parent-death policy stay in Agent Server private
runtime state. Parent bindings and spawn receipts stay in the Runtime Store.
An explicit remote child runs under the same named Jido instance on the given
Erlang node. The parent keeps the logical relationship. A failed remote request
does not fall back to the parent node. A timeout can be indeterminate.

The seam-09 Ref facade resolves a complete Ref to the current local PID at the
start of each operation. The PID is a replaceable handle. A missing local Ref
does not cause a Controller call or remote transport call.

`Jido.Topology.Controller` is an application-supervised peer of the Jido
instance. It owns declared membership, dependency order, readiness, repair,
and cleanup. The Jido instance only executes requested component lifecycle
operations.

## Four-module Plugin seam

The split Plugin modules follow code ownership, not process placement:

| Module | May own portable state | May run a live process | May persist Agent state | May select live placement |
| --- | --- | --- | --- | --- |
| `Jido.Agent.Plugin` | Yes, one declared value | No | No | No |
| `Jido.AgentServer.Plugin` | Reads its owned value | Yes, one optional root | No | No |
| `Jido.Persistence.Plugin` | Converts its owned value | No | No adapter access | No |
| `Jido.Topology.Plugin` | No live state | No | No | No; static contribution only |

This model keeps the old `Jido.Plugin` mixed-callback form as a compatibility
adapter. It does not put all owner logic back in that module.

## Canonical implementation

| Contract | Source |
| --- | --- |
| Five-child instance and `:one_for_one` strategy | `Jido.init/1` |
| Instance-local service names and `max_tasks` | `Jido` |
| Nondurable table lifetime | `Jido.RuntimeStore` |
| Managed Agent placement and restart defaults | `Jido.AgentServer` |
| Same-instance checkpoint recovery | `Jido.AgentServer.RuntimeCheckpoint` |
| Linked initial readiness and owner-linked Task workers | `Jido.AgentServer` |
| Plugin wrapper, private Supervisor, and root generation | `Jido.AgentServer.PluginLifecycle` and `Jido.AgentServer.PluginChild` |
| Fresh Plugin state-version bootstrap pair | `Jido.Plugin.Init` and `Jido.AgentServer.PluginLifecycle` |
| Logical child ownership and known-node placement | `Jido.AgentServer.DirectiveRuntime` and `Jido.AgentServer.ChildPlacement` |
| Spawn generation recovery | `Jido.AgentServer.SpawnRegistry` |
| Local Ref resolution with no fallback | `Jido.Instance.RefFacade` |
| Separate fixed-target repair owner | `Jido.Topology.Controller` |

## Evidence matrix

| Requirement group | Evidence | State |
| --- | --- | --- |
| `RT-REQ-001` to `RT-REQ-007` | Runtime topology and supervisor tests | `Proven` |
| `RT-REQ-008` to `RT-REQ-016` | Runtime topology, Agent lifecycle, checkpoint, persistence, and activation tests | `Proven` |
| `RT-REQ-017` to `RT-REQ-019` | Runtime lifecycle, runtime boundary, and Plugin lifecycle owner-death tests | `Proven` |
| `RT-REQ-020` to `RT-REQ-027` | Plugin lifecycle, runtime, validation, and four-facet tests | `Proven` |
| `RT-REQ-028` to `RT-REQ-032` | Child lifecycle and relationship recovery tests | `Proven` |
| `RT-REQ-033` to `RT-REQ-044` | Distributed child, remote lifecycle, and Spawn Registry tests | `Proven` for the bounded known-node contract |
| `RT-REQ-045` to `RT-REQ-047` | Instance Ref and stable-reference proof tests | `Proven` |
| `RT-REQ-048` | Package boundary, missing cluster services, and the named research skip | `Proven` as an explicit non-guarantee |
| `RT-REQ-049` to `RT-REQ-051` | Controller tests, application supervision guide, and topology examples | `Proven` for the runtime/control-plane split |

## Compatibility decisions

| Area | Decision |
| --- | --- |
| Instance tree | Keep five direct children and `:one_for_one`. |
| Agent pool | Keep one Agent Dynamic Supervisor. Do not add a Plugin pool in first-stage V3. |
| Agent restart | Keep managed `:transient` and direct `:temporary` defaults. |
| Plugin declaration | Require one permanent root specification. |
| Plugin hosting | Use a temporary wrapper and temporary hosted generations so replacement gets fresh input. |
| Runtime checkpoint | Keep latest-commit recovery only in one live instance generation. |
| Persistence | Keep explicit durable activation. Add no discovery or lease meaning. |
| Relationships | Keep current Directives, private handles, parent bindings, and parent-death policy. |
| Remote child | Keep explicit `node:`, no fallback, and indeterminate request tracking. |
| Identity | Keep Ref-first local resolution and current ID and PID paths. |
| Controller | Keep it outside the Jido instance. |
| Cluster features | Add no discovery, automatic placement, rebalance, failover, lease, fence, or exclusive-owner claim. |

## Limits

- A hard kill of a nested OTP supervisor can overlap the shutdown of its own
  internal children. The direct-child replacement matrix therefore uses
  `Supervisor.terminate_child/2` and `Supervisor.restart_child/2`. Worker and
  owner-death tests use abrupt exits.
- Runtime Store and Spawn Registry recovery is not durable recovery.
- A known-node request does not discover nodes or grant exclusive authority.
- Distribution loss proves that a child is unreachable. It does not prove that
  the remote process is dead.
- A stable Ref is not a location lease or write-authority grant.
- The static Controller does not add a cluster control plane.

## Verification record

Focused local topology checks passed on 2026-09-09:

```text
mix test test/jido/runtime_topology_test.exs \
  test/jido/supervisor_test.exs \
  test/jido/instance_ref_test.exs \
  test/jido/agent_server/runtime_lifecycle_test.exs \
  test/jido/agent_server/plugin_lifecycle_test.exs \
  test/jido/agent_server/runtime_boundary_test.exs \
  test/jido/agent_server/child_lifecycle_test.exs \
  test/jido/agent_server/spawn_registry_test.exs \
  test/jido/topology/controller_test.exs --seed 0

97 passed

mix test test/jido/agent_server/distributed_child_test.exs \
  test/jido/agent_server/remote_lifecycle_test.exs \
  test/jido/agent_server/distributed_authority_test.exs \
  --include research --seed 0

19 passed, 1 skipped

mix test test/examples/07_topology --only example --seed 0

6 passed

mix test test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs \
  test/examples/99_research/99_11_stable_reference/stable_reference_test.exs \
  --include example --seed 0

5 passed

mix test test/examples/99_research --include example --seed 0

42 passed, 3 skipped

mix quality

1177 passed, 1 excluded
```

The distributed skip is the explicit non-guarantee for one exclusive cluster
owner. The three research skips are the deferred live Turn, state, and
Topology upgrade contracts. The documentation warning gate and diff check
also passed.

## Completion criteria

- [x] The five direct instance children and their isolation have focused
      evidence.
- [x] `max_tasks` limits only the Task Supervisor pool.
- [x] Full instance stop removes all Dynamic Supervisor children and the
      nondurable table.
- [x] A new instance generation does not discover durable Agents.
- [x] Managed and direct Agent restart defaults have evidence.
- [x] All Agent-owned work stops on controlled and abrupt owner death.
- [x] The four Plugin owner modules have separate code contracts.
- [x] The four Plugin contracts do not imply four runtime pools.
- [x] Plugin replacement receives one matching committed state-version pair.
- [x] Plugin declaration and hosted-generation restart rules are distinct and
      documented.
- [x] Local Ref resolution has no implicit Topology or transport fallback.
- [x] Known-node results distinguish confirmed, indeterminate, and unreachable
      states.
- [x] Cluster authority and automatic placement stay outside Jido core.
- [x] Seam 11 owns desired state and repair through public runtime operations.
