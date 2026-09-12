> The topology baseline is implemented. The Agent Server work and relationship
> refinement is pending approval.

# 10 - Runtime topology

## Briefing

One Jido instance owns five local runtime services under `:one_for_one`.
Agent Servers and Plugin runtime wrappers are peer children in one Dynamic
Supervisor. A wrapper owns one private Supervisor and one Plugin runtime
generation.

The four Plugin modules define four owner contracts. They do not define four
process pools:

| Plugin owner | Runtime role |
| --- | --- |
| `Jido.Agent.Plugin` | Pure Agent preparation and owned state |
| `Jido.AgentServer.Plugin` | Live callbacks and an optional runtime root |
| `Jido.Persistence.Plugin` | Pure dump and load conversion |
| `Jido.Topology.Plugin` | Pure static Topology contribution |

Only the Agent Server facet can declare a live runtime root. For first-stage
V3, its temporary wrapper stays beside Agent Servers in the same Dynamic
Supervisor. A Plugin declaration must return a permanent root specification.
The wrapper hosts each root generation as temporary, observes its exit, gets a
new state-version bootstrap pair from the Agent Server, and starts the next
generation.

## Owned contract

- The Jido instance owns one Task Supervisor, Registry, Runtime Store, Spawn
  Registry, and Agent Dynamic Supervisor.
- `max_tasks` limits the Task Supervisor only.
- Managed Agent Servers are direct peer children and use `:transient` by
  default. Direct linked Servers use `:temporary` by default.
- Current Agent-owned workers stop on controlled or abrupt Agent Server death.
- Runtime checkpoints and spawn receipts can survive their worker restart.
  They do not survive full instance loss.
- Logical child ownership does not create a nested OTP Agent tree.
- Explicit known-node child placement has no local fallback.
- Stable Agent Refs resolve through the selected local instance. There is no
  implicit Controller or transport fallback.
- The application supervises `Jido.Topology.Controller` outside the Jido
  instance.

## Proposed Agent Server refinement

- Put all user, storage, remote, and independently timed Agent Server work
  under the instance Task Supervisor.
- Keep state, commit, relationship, Directive, and lifecycle authority in the
  private Agent Server Runtime.
- Fence every result with activation and work identity, plus the related Turn,
  version, Directive, or relationship identity when required.
- Keep logical Agent relationships and Plugin runtime children in separate
  private capability projections. Do not add a second process pool.
- Keep process-independent parent bindings in Runtime Store and distributed
  request history in Spawn Registry.

## Boundaries

This seam owns local process placement, restart coupling, shutdown coupling,
Plugin runtime hosting, logical child handles, and explicit known-node child
ownership.

It does not own Agent state, Turn rules, Plugin callback meaning, persistence
record meaning, desired Topology, repair policy, transport, discovery,
automatic placement, failover, leases, fencing, or cluster write authority.

## Baseline evidence

- `test/jido/runtime_topology_test.exs` proves the five-child inventory,
  instance isolation, direct-child replacement, Task Supervisor capacity,
  Agent and Plugin peer placement, full shutdown, new instance generation,
  and explicit durable reactivation.
- Agent Server lifecycle tests prove runtime checkpoint recovery, Plugin root
  replacement, coherent state-version input, and owner-bound work.
- Child and distributed tests prove logical ownership, known-node placement,
  indeterminate results, receipt recovery, and no local fallback.
- The topology examples prove application-supervised Controller use. The
  stable-reference example proves local handle replacement without transport
  fallback.

The expanded Task ownership, uniform result fencing, and separate private
capability projections are not implemented. Their evidence is pending.

## Follow-on seams

- 11 Topology control plane owns desired membership, activation order,
  readiness policy, repair, and cleanup.
- 13 Observability owns public runtime event and status projections.
- 99 Delivery owns the complete cross-package and release gate.

## Documents

- [Target design](design.md)
- [Alignment and evidence](alignment.md)
