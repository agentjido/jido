> Selected seam design. The Jido core contract is implemented. Distributed
> requirements are a deferred external reference contract.

# Topology control-plane design

The local requirements and decisions in this document define the implemented
Jido core seam. Requirements for a distributed control plane define a later
application or integration package. They are not Jido core V3 release gates.

## Scope and owner

- Owner: `Jido.Topology` and `Jido.Topology.Controller` own static topology,
  exact known-node execution, and lifecycle Signals. An optional host
  application or ecosystem integration owns placement policy and the
  distributed control plane.
- In scope for Jido core: static definition validation, pure Plugin
  contribution, planning, one current Controller target, additive Agent
  updates, exact node placement, lifecycle Signals, readiness, repair, lookup,
  and cleanup.
- External reference scope: provider inputs for membership and authority,
  placement output, authority epochs, handoff, recovery, network-partition
  safety, operator controls, and distributed observation.
- Out of scope: the local OTP process tree, Agent and Turn semantics,
  persistence record format, membership or consensus implementation,
  transport, deployment, business workflow, and vendor selection.
- Adjacent owners: seam 03 owns Agent Ref. Seam 06 owns commit. Seam 07 owns
  durable Agent records. Seam 08 owns one Agent activation. Seam 09 owns local
  Ref resolution. Seam 10 owns local process placement and known-node child
  operations. Seam 12 owns public errors. Seam 13 owns event schemas.

## Model

Jido core supplies a local execution component. A distributed control plane is
an optional coordinator above it:

```text
desired placement + stable Agent Refs
                 |
membership view + authority grants + capacity
                 |
        control-plane decision
                 |
public Jido activation, stop, status, and persistence boundaries
                 |
       one local Agent activation
```

Before activation, pure instance planning asks declared
`Jido.Topology.Plugin` facets for canonical static entries. It appends Agent
contributions, then group contributions, in source and Plugin declaration
order. Included Topologies expand in their own scopes. The common validator
checks the complete result. The source definition stays unchanged.

The Topology Controller has one current `%Jido.Topology.Instance{}` target. It
repairs members of that target on one named Jido instance. An explicit update
can add Agents while every existing Agent and resource specification stays
unchanged. A declaration or live placement call can name an exact Erlang node.
The Controller does not discover nodes, select a node, remove live members,
issue authority, or resolve a network partition.

The optional control plane uses these logical values. Exact public type names
remain open.

| Value | Required meaning | Excluded meaning |
| --- | --- | --- |
| Membership view | Provider snapshot of node ID, generation, availability, labels, capacity, and observation time | Agent identity or write authority |
| Desired placement | Stable Agent Ref, definition coordinates, constraints, and requested operating state | PID or current node |
| Location record | Ref, node, activation identity, authority epoch, and readiness state | Proof that the holder can still write |
| Authority grant | Exact Ref, holder identity, monotonically increasing epoch, validity result, and optional expiry | Membership, Agent state version, or storage revision |
| Control operation | Stable operation ID, kind, input generation, target, phase, and result | Agent checkpoint or private runtime state |

An authority epoch is a fencing value. A higher epoch supersedes every lower
epoch for the same Ref. If a deployment uses time-limited leases, lease expiry
limits holder eligibility. It does not replace epoch checks. A system cannot
claim exclusive ownership unless every protected commit rejects a stale epoch.
Capability-specific external effects need the same rule if they claim fencing.

## Jido core requirements

### Purpose and boundary

`TOP-REQ-001`: The Jido core topology boundary shall validate static Topology
definitions and build local execution plans without starting processes.

`TOP-REQ-002` is retired. It required every repair to use only the instance
supplied at startup. `TOP-REQ-069` and `TOP-REQ-076` replace that requirement
without assigning new meaning to its identifier.

`TOP-REQ-003`: The Jido core package shall keep cluster membership, automatic
placement, rebalance, failover, leases, and fencing outside core.

`TOP-REQ-004`: Where a distributed control plane is enabled, the control-plane
owner shall use documented public Jido activation, lifecycle, persistence, and
inspection boundaries.

`TOP-REQ-005`: The control-plane owner shall keep desired placement, runtime
location, and write authority as separate values.

## External distributed reference requirements

Requirements `TOP-REQ-006` through `TOP-REQ-058` and `TOP-REQ-061` apply only
if an application or integration package implements a distributed control
plane. Jido core does not implement them. Their deferred state does not block
the local core contract.

### Membership and discovery inputs

`TOP-REQ-006`: When the membership provider publishes a view, the
control-plane boundary shall validate each node ID, membership generation,
availability state, label set, capacity value, and observation time.

`TOP-REQ-007`: If one membership view contains duplicate node IDs, then the
control-plane boundary shall reject that view before it makes a placement
decision.

`TOP-REQ-008`: When two membership views have the same provider identity, the
control-plane boundary shall reject a view with a generation lower than the
last accepted generation.

`TOP-REQ-009`: When membership marks a node unavailable, the control-plane
boundary shall treat the node as ineligible for new placement.

`TOP-REQ-010`: If membership or discovery input is unavailable or invalid,
then the control-plane boundary shall start no new placement, handoff, or
automatic recovery operation from that input.

`TOP-REQ-011`: When the control plane consumes membership data, it shall not
treat node presence or health as proof of Agent ownership.

### Exclusive ownership, leases, and epochs

`TOP-REQ-012`: Where exclusive distributed ownership is enabled, the authority
provider shall issue one validated grant for an exact Agent Ref and holder.

`TOP-REQ-013`: When authority for one Agent Ref moves to another holder, the
authority provider shall issue an epoch greater than every epoch that it
previously issued for that Ref.

`TOP-REQ-014`: Where exclusive distributed ownership is enabled, when the
control plane starts an activation, it shall supply the current authority epoch
through the approved activation boundary.

`TOP-REQ-015`: If an activation presents an epoch lower than the current epoch
for its Agent Ref, then the protected commit boundary shall reject the commit
before it makes Agent state visible.

`TOP-REQ-016`: Where grants have an expiry, when a holder can no longer confirm
grant validity, the activation authority boundary shall stop new mutating Turns
before the grant expires.

`TOP-REQ-017`: If the runtime cannot reject stale epochs at every protected
commit, then the control-plane boundary shall not report exclusive ownership or
safe automatic failover.

`TOP-REQ-018`: When persistence compare-and-swap reports a conflict, the
control-plane boundary shall not treat that conflict result as a new authority
grant.

### Placement decisions

`TOP-REQ-019`: When the control plane selects a node, it shall use one accepted
desired-placement revision and one accepted membership view.

`TOP-REQ-020`: When the control plane selects a node, it shall exclude nodes
that do not satisfy declared labels, capacity, availability, and placement
constraints.

`TOP-REQ-021`: When equal inputs reach the placement policy, the placement
policy shall return the same selected node and explanation.

`TOP-REQ-022`: When the selected node changes, the control-plane boundary shall
preserve the exact Agent Ref.

`TOP-REQ-023`: Before a placement operation starts a process, the
control-plane boundary shall validate the target definition, Agent Ref,
authority grant, target node, and operation revision.

`TOP-REQ-024`: If no eligible node exists, then the control-plane boundary
shall record an unscheduled result without starting an Agent.

### Handoff and recovery authority

`TOP-REQ-025`: When the control plane starts a handoff or recovery operation,
it shall assign one stable operation ID before the first runtime side effect.

`TOP-REQ-026`: When a target activation becomes eligible to accept mutating
Turns, the authority boundary shall already have fenced every lower epoch for
that Agent Ref.

`TOP-REQ-027`: Where durable persistence is configured, when a handoff or
recovery target starts, the target Agent Server shall restore the latest valid
record before it reports readiness.

`TOP-REQ-028`: When a target activation reports ready with the current epoch,
the control-plane boundary shall publish its location as the current observed
location.

`TOP-REQ-029`: If target activation or readiness fails, then the control-plane
boundary shall record a failure result that identifies the last completed phase
and excludes the target from the current location.

`TOP-REQ-030`: When membership loss triggers automatic recovery, the
control-plane boundary shall acquire a new authority epoch before it starts the
replacement activation.

`TOP-REQ-031`: When the control plane retries the same incomplete operation, it
shall keep the operation ID and reject changed immutable operation input.

`TOP-REQ-032`: When an operator rolls back a completed handoff, the
control-plane boundary shall create a new forward operation with a newer
authority epoch.

`TOP-REQ-033`: The control-plane boundary shall not copy or edit Agent
checkpoint data during placement, handoff, or recovery.

### Stable Ref resolution

`TOP-REQ-034`: When desired placement names an Agent, the control-plane
boundary shall use the complete seam-03 Agent Ref as the logical identity.

`TOP-REQ-035`: When a control operation needs a runtime handle, the
control-plane boundary shall resolve the current location for the complete Ref
at the start of that operation.

`TOP-REQ-036`: If a resolved PID, node, or location record becomes stale, then
the control-plane boundary shall keep the Agent Ref unchanged.

`TOP-REQ-037`: When an operation retries after a stale-location result, the
control-plane boundary shall resolve the Ref again before it sends a second
runtime request.

`TOP-REQ-038`: If a Ref has no current location, then the control-plane
boundary shall start an activation only from an accepted desired-placement and
authority decision.

### Network partitions and fencing

`TOP-REQ-039`: While a node cannot confirm current authority, the activation
authority boundary shall reject new Agent state commits on that node.

`TOP-REQ-040`: While a node cannot confirm current authority, the
control-plane boundary shall report the affected placement as unavailable or
fenced and not as ready.

`TOP-REQ-041`: When a protected recoverable external effect claims fencing,
the capability owner shall give the receiver the current authority epoch and
require rejection of lower epochs.

`TOP-REQ-042`: When network connectivity returns, the control-plane boundary
shall select the location with the highest valid authority epoch as the only
eligible mutation owner.

`TOP-REQ-043`: When network connectivity returns, the control-plane boundary
shall stop or fence every observed activation with a lower epoch.

`TOP-REQ-044`: The control-plane boundary shall not infer network-partition
policy from the `partition` field of an Agent Ref.

### Observability

`TOP-REQ-045`: When membership, placement, authority, handoff, recovery, or an
operator action changes state, the control-plane boundary shall emit one
bounded semantic event for that transition.

`TOP-REQ-046`: When the control-plane boundary emits a semantic event, it shall
include only registered operation, Ref, node, epoch, phase, and result fields.

`TOP-REQ-047`: When the control-plane boundary reports status, it shall
separate desired placement, observed location, authority state, active
operation, and last error.

`TOP-REQ-048`: If an observation handler fails, then the control-plane boundary
shall preserve the placement, authority, and runtime result.

### Operator actions

`TOP-REQ-049`: When an operator action is accepted, the control-plane boundary
shall record the authenticated actor, stable request ID, action, target, input
revision, and result.

`TOP-REQ-050`: When an operator cordons a node, the placement policy shall
exclude that node from new placements.

`TOP-REQ-051`: When an operator uncordons a node, the placement policy shall
restore eligibility only after current membership and placement constraints
accept that node.

`TOP-REQ-052`: When an operator drains a node, the control-plane boundary shall
move or stop each selected placement through a separate fenced operation.

`TOP-REQ-053`: When an operator requests a move, the control-plane boundary
shall target one exact Agent Ref and one eligible destination.

`TOP-REQ-054`: When an operator requests a rebalance, the control-plane
boundary shall create a separate bounded operation for each selected Agent
Ref.

`TOP-REQ-055`: When an operator suspends automatic recovery for an Agent Ref,
the control-plane boundary shall start no automatic recovery operation for
that Ref until resume.

`TOP-REQ-056`: When an operator resumes automatic recovery for an Agent Ref,
the control-plane boundary shall evaluate current desired placement,
membership, location, and authority before it acts.

`TOP-REQ-057`: If an operator requests a force action, then the control-plane
boundary shall still enforce Ref validation, authority epochs, and fencing.

`TOP-REQ-058`: When an operator requests a preview, the control-plane boundary
shall return the proposed placement operations without changing authority,
location, or runtime state.

## Compatibility and Plugin planning requirements

### Core compatibility

`TOP-REQ-059`: While no approved migration replaces static Topology, the
Jido core package shall keep its definition, Builder, Codec, instance, plan,
Controller, readiness, repair, and lookup contracts supported.

`TOP-REQ-060`: While live target replacement is not implemented, the local
Topology Controller shall not describe `reconcile/2` as resize, upgrade,
rebalance, handoff, or recovery.

### External error ownership

`TOP-REQ-061`: When a distributed control-plane operation fails outside a
documented provider protocol, the control-plane owner shall return an
owner-defined error through the approved seam-12 contract.

### Core authority boundary

`TOP-REQ-062`: The control-plane boundary shall not start an authoring owner
Agent or Plugin runtime as implicit distributed authority.

### Topology Plugin planning

`TOP-REQ-063`: When Jido builds a Topology instance or a direct Plan, it shall
ask every declared Topology Plugin facet for its static contribution before it
builds the complete graph.

`TOP-REQ-064`: When Jido orders Topology contributions, it shall process Agent
declarations, then group declarations, in source order and shall preserve the
Plugin order inside each declaration.

`TOP-REQ-065`: When an included Topology contains a contributing Plugin, Jido
shall apply that contribution in the included Topology scope.

`TOP-REQ-066`: Before a Controller can activate a contributed plan, Jido shall
apply common definition and graph validation to all explicit and contributed
entries.

`TOP-REQ-067`: When planning adds Plugin entries, the Topology instance shall
retain the validated source definition and shall put expanded entries only in
the Plan.

`TOP-REQ-068`: The Topology Plugin contract shall provide no runtime handle or
operation that starts a process, persists Agent state, replaces a Controller
target, or grants live or distributed authority.

### Additive target update

`TOP-REQ-069`: When a Controller accepts an additive target update, the
Controller shall replace its current repair target with the validated target.

`TOP-REQ-070`: Before a target update has live effects, the Controller
shall validate the target definition and input through normal Topology
instantiation.

`TOP-REQ-071`: If a target update changes topology identity, any resource, or
an existing Agent specification, then the Controller shall reject the update
without changing a live member.

`TOP-REQ-072`: If a target update removes an existing Agent, then the
Controller shall reject the update without changing a live member.

`TOP-REQ-073`: If a target update is requested during an active repair pass,
then the Controller shall reject the update without changing the current
target.

`TOP-REQ-074`: When an accepted target adds Agents, the Controller shall start
them through the normal dependency, concurrency, timeout, readiness, and
ownership checks.

`TOP-REQ-075`: When an accepted target retains an existing Agent specification,
the Controller shall keep that Agent PID and committed state.

`TOP-REQ-076`: When a later repair pass runs after an accepted update, the
Controller shall repair the updated target.

### Canonical DSL, lifecycle, and exact placement

`TOP-REQ-077`: The Topology DSL shall accept `agent`, `routes`, and `topology`
as root sections.

`TOP-REQ-078`: The Topology DSL shall accept topology-specific sections only
inside `topology`.

`TOP-REQ-079`: The Topology DSL shall permit `agent` and `topology` to be
present or absent independently.

`TOP-REQ-080`: When a Topology module declares `routes`, the Agent DSL shall
require an explicit `agent` block and shall apply the normal Agent route rules.

`TOP-REQ-081`: The Topology authoring boundary shall not start the control
Agent when it constructs a topology instance.

`TOP-REQ-082`: Where a lifecycle target is configured, the Controller shall
accept only an Agent PID or `Jido.Agent.Ref`.

`TOP-REQ-083`: Where a lifecycle target is configured, when an operation or
component changes state, the Controller shall send a Signal in the
`jido.topology.lifecycle` namespace.

`TOP-REQ-084`: If lifecycle Signal delivery fails, then the Controller shall
preserve the activation, repair, update, placement, or cleanup result.

`TOP-REQ-085`: When the Controller emits a lifecycle Signal, it shall include
only bounded topology, operation, component, node, status, and error-code data.

`TOP-REQ-086`: The Controller shall not execute placement or rebalance policy
as part of lifecycle Signal delivery.

`TOP-REQ-087`: When an Agent or group declaration contains `node`, the Plan
shall resolve it to one exact Erlang node before activation.

`TOP-REQ-088`: When an Agent or group declaration omits `node`, the Plan shall
use the Controller node.

`TOP-REQ-089`: When `place_agent/4` accepts an exact node, the Controller shall
stop the owned Agent before it starts a repair pass for that node.

`TOP-REQ-090`: The Controller shall not discover nodes or select a placement
target.

`TOP-REQ-091`: If exact remote activation fails, then the Controller shall not
fall back to local activation.

`TOP-REQ-092`: If a remote Agent declares a subscription to a Controller-owned
local Bus, then plan construction shall reject the plan.

`TOP-REQ-093`: If the Controller cannot confirm the old remote Agent state
during placement, then it shall reject the placement as uncertain before it
starts an Agent on another node.

`TOP-REQ-094`: The Controller shall expose the effective node for one planned
Agent through `agent_node/3`.

`TOP-REQ-095`: The Topology Codec shall encode and decode only the current V3
version-2 document format.

`TOP-REQ-096`: The Topology startup contract shall treat readiness as all
planned components ready and shall not expose a readiness policy option.

`TOP-REQ-097`: The Topology definition shall keep a general resources
collection while Bus remains the first implemented core resource type.

`TOP-REQ-098`: When exact placement starts an Agent on a new node, the
Controller shall use the normal restore contract and shall otherwise use the
declared initial state.

`TOP-REQ-099`: If the Controller Runtime restarts while its Jido instance stays
live, then the Controller shall retain accepted placement overrides for its
current definition.

`TOP-REQ-100`: Core resource kinds shall use one internal resource boundary for
validation, lookup, startup, and ownership checks. Decoded definitions shall
not select arbitrary runtime modules.

`TOP-REQ-101`: Each Topology lifecycle event shall be a custom `Jido.Signal`
module. The Controller shall not expose separate lifecycle Signal factory
functions.

## Public contract

The implemented core surface remains the local component contract:

| Role | Current public entry | Meaning |
| --- | --- | --- |
| Static authoring | `Jido.Topology`, DSL, Builder, Codec | Validated definition; no processes |
| Pure plan | `Jido.Topology.instantiate/2`, `Jido.Topology.Plan.build/3` | Validated input, Plugin contribution, exact nodes, and stable IDs |
| Activation | `Jido.Topology.Controller.start_link/1` | One current target on one Jido instance |
| Readiness | `await_ready/2`, `status/2` | Current pass and component state |
| Repair | `reconcile/2` | Repair the current target; not an update |
| Update | `update/3` | Add Agents while existing Agents and resources stay unchanged |
| Placement | `place_agent/4`, `agent_node/3` | Apply and inspect a caller-selected exact node |
| Lifecycle | Controller `:lifecycle` option and custom modules under `Jido.Topology.Signal` | Best-effort Signals to a control Agent |
| Lookup | `whereis_agent/3`, `whereis_bus/2`, `whereis/2` | Replaceable runtime handles |

This design does not add a required control plane to Jido core. An ecosystem
contract can define provider behaviours for membership, authority, desired
placement storage, and location publication. Those providers must have closed
validated result sets, operation limits, and fault classification. This seam
does not select a library, consensus system, database, or transport.

An authority grant is required only for deployments that claim distributed
exclusive ownership or automatic failover. A deployment without enforceable
fencing can still use best-effort placement. Its public status and docs must
state that it provides no exclusive-owner guarantee.

## Invariants

- `TOP-INV-001`: Static local repair and distributed control-plane policy have
  separate owners.
- `TOP-INV-002`: Stable Agent identity, desired placement, runtime location,
  and write authority are separate values.
- `TOP-INV-003`: Membership is input to placement. It is not write authority.
- `TOP-INV-004`: A higher authority epoch fences every lower epoch for one Ref.
- `TOP-INV-005`: Handoff and recovery never edit Agent checkpoint content.
- `TOP-INV-006`: Network availability cannot override fencing.
- `TOP-INV-007`: Operator actions cannot bypass authority checks.
- `TOP-INV-008`: Control-plane observation has no execution authority.
- `TOP-INV-009`: Topology Plugin contribution changes a Plan, not its source
  definition or runtime authority.

## Downstream guarantees

| Consumer seam | Selected guarantee |
| --- | --- |
| 13 Observability | Control-plane transitions have bounded semantic facts and no Agent state or private handles. |
| 99 Delivery | Each distributed claim has provider, failure, partition, compatibility, and acceptance evidence. |
| Ecosystem control plane | Public Jido activation and persistence components stay distinct from membership and authority policy. |
| Host application | A control plane is optional and can be selected without changing core Agent semantics. |

## Selected design decisions

| ID | Selected option | Effect |
| --- | --- | --- |
| `TOP-DEC-001` | Distributed control-plane code lives in an application or focused ecosystem package, not Jido core. | The core boundary stays local. |
| `TOP-DEC-002` | Keep static Topology and fixed-target repair. | Existing users keep a supported component. |
| `TOP-DEC-003` | An exclusive-owner claim requires an increasing epoch enforced at every protected commit. | Lease and Registry presence are not enough. |
| `TOP-DEC-004` | Time-limited leases are optional, but fencing is required for an exclusive claim. | The external design stays provider-neutral. |
| `TOP-DEC-005` | Membership is advisory placement input only. | Membership failure cannot grant ownership. |
| `TOP-DEC-006` | An external placement policy must be deterministic and explain its result. | The contract does not select one policy. |
| `TOP-DEC-007` | Handoff restores through the normal durable Agent record. | The control plane does not copy checkpoint content. |
| `TOP-DEC-008` | A holder rejects new mutations when it cannot confirm current authority. | Safety takes priority over write availability. |
| `TOP-DEC-009` | Preview, cordon, uncordon, drain, move, rebalance, suspend, resume, and status belong to the external contract. | Product UI stays outside this seam. |
| `TOP-DEC-010` | An owner Agent is not the control plane. | Authoring and Plugin-owned Agent fields do not become cluster authority. |
| `TOP-DEC-011` | Support additive Agent target updates and keep removal, replacement, and resource changes deferred. | Growth does not imply rebalance, handoff, or distributed authority. |
| `TOP-DEC-012` | Topology Plugin facets contribute during pure Plan construction. | Static extension is complete without live Plugin authority. |
| `TOP-DEC-013` | Keep one root DSL shape: optional `agent`, Agent-compatible `routes`, and optional `topology`. | Topology-specific sections have one location. |
| `TOP-DEC-014` | Send lifecycle state as best-effort Signals to an optional control Agent. | Policy uses normal routes and Plugin boundaries. |
| `TOP-DEC-015` | Keep exact known-node placement in core and keep node selection and rebalance policy outside core. | Core supplies a small mechanism without becoming a cluster manager. |
| `TOP-DEC-016` | Keep the resources collection general while Bus is the first core type. | Later resource types do not require a new top-level model. |
| `TOP-DEC-017` | Use one closed resource boundary inside core. | The Controller stays general without letting documents select code. |
| `TOP-DEC-018` | Define each lifecycle event with `use Jido.Signal`. | Signal type, schema, and construction use the standard Signal contract. |
