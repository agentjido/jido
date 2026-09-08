> Target seam design. This document is pending approval.

# Runtime topology design

All requirements and decisions are recommended targets. EARS syntax does not
mean that the user approved them. Code defines current behavior until an
approved target is implemented.

## Scope and owner

- Owner: the local OTP runtime topology below one Jido instance.
- In scope: supervisors, registries, dynamic child placement, child ownership,
  restart and shutdown coupling, Plugin runtime placement, logical runtime
  relationships, known-node child placement, and integration points for local
  Agent Ref resolution.
- Out of scope: Agent and Plugin state meaning, Turn and commit behavior,
  persistence record meaning, Ref fields, namespace binding, desired topology,
  readiness policy for a complete topology, live target changes, transport,
  automatic cluster placement, leases, fencing, and deployment.
- Adjacent owners: seam 05 owns Plugin callbacks and bootstrap values. Seam 07
  owns durable records. Seam 08 owns Agent Server state-machine behavior. Seam
  09 owns the instance facade and local Ref resolution. Seam 11 owns topology
  activation and repair.

## Model

The first-stage target keeps the implemented local shape:

```text
Application Supervisor
├── Jido instance                         :one_for_one
│   ├── Task Supervisor                   bounded runtime work
│   ├── Registry                          unique local names
│   ├── Runtime Store                     nondurable instance coordination
│   ├── Spawn Registry                    known-node spawn receipts
│   └── Agent Dynamic Supervisor
│       ├── Agent Server                  transient by default
│       └── Plugin runtime wrapper        temporary
│           └── private Supervisor
│               └── Plugin runtime root   permanent
└── Topology Controller                   separate seam-11 child, when used
```

The application owns the Supervisor above these children. The five instance
services have separate local names. Agent Servers and Plugin wrappers have
different logical roles, but the first target does not require separate pools.

A logical child relationship does not create a nested OTP Agent tree. The
target Jido instance owns each local Agent Server process. A parent Agent Server
owns the logical link and the policy for parent death. For an explicit remote
child, the target node's same-named Jido instance owns the process and runtime
work. The parent still owns the logical link.

Stable identity, current location, and write authority are separate. A future
Agent Ref can remain stable while a local PID changes. The instance facade
resolves local Refs. This seam does not create a distributed directory or
grant exclusive write authority.

## Requirements

### Local instance topology

`RT-REQ-001`: When a Jido instance starts, the runtime topology shall start one
Task Supervisor, one unique-key Registry, one Runtime Store, one Spawn Registry,
and one Agent Dynamic Supervisor.

`RT-REQ-002`: While the first-stage topology is active, the Jido instance
Supervisor shall use the `:one_for_one` strategy for its five standard children.

`RT-REQ-003`: When two Jido instances use different local names, the runtime
topology shall give each instance a separate name for every standard child.

`RT-REQ-004`: When the Runtime Store worker restarts inside a live Jido
instance, the runtime topology shall retain the instance-owned ETS table and
its entries.

`RT-REQ-005`: When the complete Jido instance stops, the runtime topology shall
remove its nondurable Runtime Store table and entries.

`RT-REQ-006`: Where `max_tasks` is configured, the Jido instance shall apply
that value only to the Task Supervisor child limit.

`RT-REQ-007`: When an application stops a Jido instance, the instance
Supervisor shall stop its Agent Dynamic Supervisor and all children owned by
that Dynamic Supervisor before the instance shutdown completes.

### Agent Server placement and restart coupling

`RT-REQ-008`: When the Jido instance starts a managed Agent Server, the runtime
topology shall place it as a direct child of the Agent Dynamic Supervisor.

`RT-REQ-009`: While several Agent Servers are live, the runtime topology shall
keep them as peer children of the Agent Dynamic Supervisor regardless of
logical parent-child relationships.

`RT-REQ-010`: When managed Agent Server startup does not specify a restart
value, the Agent Server child specification shall use `:transient`.

`RT-REQ-011`: When a directly linked Agent Server has no Jido instance, its
child specification shall default to `:temporary`.

`RT-REQ-012`: Where a nonpersistent Agent Server runs in a named live Jido
instance, when that Server restarts abnormally, it shall restore the latest
in-instance runtime checkpoint and matching state version.

`RT-REQ-013`: When a nonpersistent Agent Server stops cleanly, the Agent Server
shall remove its in-instance runtime checkpoint.

`RT-REQ-014`: When a complete Jido instance restarts, the runtime topology
shall not treat its removed runtime checkpoints as durable recovery data.

`RT-REQ-015`: Where durable persistence is configured, when an Agent Server
restarts, the Agent Server shall use the seam-07 record contract as its durable
restart source.

`RT-REQ-016`: When no Agent Server child specification or external controller
requests activation after an instance restart, the Jido instance shall not
discover and start durable Agents by itself.

### Owned tasks and Plugin runtimes

`RT-REQ-017`: When an Agent Server starts an asynchronous admission, execution,
Plugin Directive, or error-policy worker, the runtime topology shall run that
worker under the selected Jido instance Task Supervisor.

`RT-REQ-018`: If an Agent Server stops while it owns admission, execution,
Directive, readiness, or error-policy work, then the runtime topology shall stop
that owned work before termination completes.

`RT-REQ-019`: When an Agent Server receives a late or duplicate result from
owned work, the Agent Server shall reject that result from changing committed
Agent state.

`RT-REQ-020`: Where a Plugin declares one runtime root, the runtime topology
shall place one temporary Plugin wrapper as a peer in the Agent Dynamic
Supervisor.

`RT-REQ-021`: When a Plugin wrapper starts its Plugin runtime root, the wrapper
shall own one private Supervisor whose Plugin root uses `restart: :permanent`.

`RT-REQ-022`: If the owning Agent Server stops, then the Plugin wrapper shall
stop its Plugin runtime root and then stop.

`RT-REQ-023`: When a Plugin runtime root restarts, the Agent Server and Plugin
wrapper shall keep inspection responsive while readiness runs.

`RT-REQ-024`: When the Agent Server starts or replaces a Plugin runtime, it
shall provide the latest committed owned Plugin state and matching Agent state
version in one immutable bootstrap value.

`RT-REQ-025`: If initial or replacement Plugin readiness fails or reaches its
limit, then the Agent Server shall fail the activation after it stops the
unready generation under the seam-08 lifecycle contract.

`RT-REQ-026`: When a Plugin has no runtime root, the Agent Server shall handle
its owned post-commit Directive only through the process-free contract declared
by seam 05.

`RT-REQ-027`: The runtime topology shall keep task PIDs, Plugin runtime PIDs,
monitors, timers, and child handles outside Agent state and checkpoints.

### Logical child ownership

`RT-REQ-028`: When an Agent Server starts, adopts, addresses, or stops a logical
child, it shall keep the child handle and monitor in private runtime state.

`RT-REQ-029`: When an Agent Server creates a logical child relationship in a
named Jido instance, it shall store the parent binding in the instance Runtime
Store.

`RT-REQ-030`: When an owned child exits, the parent Agent Server shall remove
the stale runtime handle before it reports the exit to Agent behavior as a
later Signal.

`RT-REQ-031`: When a logical parent exits, the child Agent Server shall apply
the configured `:stop`, `:continue`, or `:emit_orphan` parent-death policy.

`RT-REQ-032`: When a permanent child restart specification runs after its
parent activation is gone, the child placement boundary shall not recreate the
child for that stopped parent activation.

### Explicit remote-owned children

`RT-REQ-033`: When `SpawnAgent` omits a node, the child placement boundary
shall target the parent's current Erlang node.

`RT-REQ-034`: When `SpawnAgent` supplies an Erlang node, the child placement
boundary shall target the same-named Jido instance on that node.

`RT-REQ-035`: When an explicit remote target accepts a child, that target Jido
instance shall own the child process, Plugin processes, and execution work.

`RT-REQ-036`: If explicit remote child startup cannot reach its target, then
the child placement boundary shall not start the child on the parent node.

`RT-REQ-037`: If remote startup times out or loses its connection after the
request can have reached the target, then the Agent Server shall return an
indeterminate child-start result that contains the retained request identity.

`RT-REQ-038`: When a parent retries the same unresolved child request, the
child placement boundary shall use the same generation and opaque request
reference.

`RT-REQ-039`: If a retry changes the unresolved request's tag, target, Agent,
options, metadata, or restart policy, then the Agent Server shall preserve the
unresolved request and return a changed-request error.

`RT-REQ-040`: When the target Spawn Registry closes a request generation, it
shall prevent a late duplicate of that generation from recreating the child.

`RT-REQ-041`: When the Spawn Registry process restarts inside the same live
Jido instance, it shall restore its newest request records from Runtime Store.

`RT-REQ-042`: If a remote child stop cannot retire its spawn request, then the
parent Agent Server shall keep the child relationship and report the stop
failure.

`RT-REQ-043`: If distribution loss makes a remote child unreachable, then the
parent Agent Server shall classify the observation as unreachable instead of
confirmed child death.

`RT-REQ-044`: When the default remote parent-death policy detects parent exit
or distribution loss, the remote child shall stop its owned runtime work.

### Ref resolution, limits, and control-plane separation

`RT-REQ-045`: Where the seam-03 Agent Ref is enabled, when a runtime operation
needs a local Agent handle, the instance facade shall resolve the complete Ref
through the selected local instance at the start of that operation.

`RT-REQ-046`: When Ref resolution returns a PID, the runtime topology shall
identify that PID as a replaceable local handle outside the Ref.

`RT-REQ-047`: If a Ref has no live handle in the selected local instance, then
the instance facade shall not use a Topology Controller or transport as an
implicit fallback.

`RT-REQ-048`: The Jido core runtime topology shall not provide cluster
discovery, automatic placement, rebalance, failover, leases, fencing, or
exclusive cluster write authority.

`RT-REQ-049`: Where an application uses `Jido.Topology.Controller`, the
application shall supervise that Controller outside the Jido instance
Supervisor.

`RT-REQ-050`: When a Topology Controller activates or repairs a target, the
Controller shall own desired membership, dependency order, readiness policy,
repair timing, and cleanup policy under the seam-11 contract.

`RT-REQ-051`: When the runtime topology starts or stops a component for a
Topology Controller, it shall execute the normal Jido lifecycle operation
without selecting the desired target.

## Public contract

The first-stage contract keeps these implemented public roles:

| Role | Public entry or value | Meaning |
| --- | --- | --- |
| Instance topology | `Jido.child_spec/1`, `Jido.start_link/1`, generated instance child specs | Standard local OTP ownership |
| Local names | Registry, Task Supervisor, Runtime Store, and Agent Supervisor name helpers | Replaceable local service handles |
| Agent lifecycle | `start_agent`, `stop_agent`, `whereis_agent`, `hibernate`, `thaw` | Current ID, PID, name, and partition compatibility |
| Runtime inspection | `Jido.AgentServer.status/2`, `children/2`, `creation_info/2` | Bounded current activation data |
| Relationships | built-in child Directives and `agent_parent_binding` | Private live handles plus instance-scoped binding data |
| Remote placement | `Directive.spawn_agent/3` with top-level `node:` | Explicit known-node request, not discovery |

`node:` is an Erlang node atom. The target must run compatible Agent code and
the same named Jido instance. Agent Server options remain in `opts`; a node
inside `opts` is invalid. An explicit target never falls back to local start.

Remote request records are nondurable instance coordination data. They can
survive a Spawn Registry worker restart. They do not survive loss of the target
Jido instance or VM. A successful command confirms the Agent commit. It does
not confirm later child creation when the Directive result is indeterminate.

The Ref-first facade is additive and belongs to seam 09. This seam defines only
how a resolved handle enters the runtime topology. Current ID and PID APIs stay
supported until a separate migration is approved and proved.

## Invariants

- `RT-INV-001`: A logical Agent relationship does not define an OTP supervisor
  hierarchy.
- `RT-INV-002`: Agent identity, runtime location, activation identity, state
  version, and write authority remain separate.
- `RT-INV-003`: Runtime handles do not enter portable Agent or Plugin state.
- `RT-INV-004`: Explicit remote placement never implies local fallback.
- `RT-INV-005`: A known-node request is not a cluster discovery or authority
  contract.
- `RT-INV-006`: Runtime topology supplies owned components; the topology
  control plane decides desired state and repair.

## Downstream guarantees

| Consumer seam | Guaranteed contract after approval |
| --- | --- |
| 11 Topology control plane | Local components, readiness calls, temporary Agent specs, parent bindings, and cleanup operations exist without owning desired state. |
| 13 Observability | Runtime events can distinguish exit, unreachable state, restart, and indeterminate completion without exposing private handles as identity. |
| 99 Delivery | The retained local topology and remote limits have failure-injection and compatibility gates. |
| External cluster owner | Core accepts explicit known-node placement but supplies no election, lease, fencing, or failover promise. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `RT-DEC-001` | Which instance supervision shape is the first V3 target? | Keep five standard children under `:one_for_one`. | No unproved restart cascade is added. |
| `RT-DEC-002` | Does Plugin runtime need a separate pool? | No for first-stage V3. Keep temporary wrappers in the Agent pool. | Logical ownership does not require a new supervisor. |
| `RT-DEC-003` | Which Plugin root restart rule applies? | Keep one permanent root under a temporary owner-bound wrapper. | Internal restart stays bounded by Agent lifetime. |
| `RT-DEC-004` | Which nonpersistent restart source applies? | Keep the latest same-instance runtime checkpoint. | Abnormal Server restart preserves committed state, but instance loss does not. |
| `RT-DEC-005` | Do logical relationships remain in core? | Keep current private records, Runtime Store bindings, and built-in child Directives. | Existing Agent and Controller behavior remains compatible. |
| `RT-DEC-006` | What does core remote placement guarantee? | Explicit known-node ownership, no local fallback, and indeterminate request tracking only. | Core does not claim automatic recovery or exclusive ownership. |
| `RT-DEC-007` | How does Agent Ref enter this seam? | Resolve locally through seam 09 at each operation and keep PID compatibility. | Identity can outlive a process without adding remote discovery. |
| `RT-DEC-008` | Who owns activation and repair of a declared Topology? | Keep it in seam 11 and in an application-supervised Controller. | The Jido instance remains a component runtime, not a control plane. |
