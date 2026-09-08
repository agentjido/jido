> Target seam design. This document is pending approval.

# Topology control-plane design

All requirements and decisions are recommended targets. Code defines current
behavior until the target is approved and implemented.

## Scope and owner

- Owner: `Jido.Topology` and `Jido.Topology.Controller` own static local
  topology. An optional host application or ecosystem integration owns the
  distributed control plane.
- In scope: the boundary between desired placement and local activation,
  provider inputs for membership and authority, placement output, ownership
  epochs, handoff, recovery, stable Ref resolution, network-partition safety,
  operator controls, and control-plane observation.
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

The local Topology Controller has one immutable `%Jido.Topology.Instance{}`
target. It repairs members of that target on one Jido instance. It does not
discover nodes, move Agents, replace its target, issue authority, or resolve a
network partition.

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

## Requirements

### Purpose and boundary

`TOP-REQ-001`: The Jido core topology boundary shall validate static Topology
definitions and build local execution plans without starting processes.

`TOP-REQ-002`: When the local Topology Controller reconciles, it shall repair
only the fixed `%Jido.Topology.Instance{}` supplied at startup.

`TOP-REQ-003`: The Jido core package shall keep cluster membership, automatic
placement, rebalance, failover, leases, and fencing outside core.

`TOP-REQ-004`: Where a distributed control plane is enabled, the control-plane
owner shall use documented public Jido activation, lifecycle, persistence, and
inspection boundaries.

`TOP-REQ-005`: The control-plane owner shall keep desired placement, runtime
location, and write authority as separate values.

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

### Compatibility and errors

`TOP-REQ-059`: While no approved migration replaces static local Topology, the
Jido core package shall keep its definition, Builder, Codec, instance, plan,
Controller, readiness, repair, and lookup contracts supported.

`TOP-REQ-060`: While live target replacement is not implemented, the local
Topology Controller shall not describe `reconcile/2` as resize, upgrade,
rebalance, handoff, or recovery.

`TOP-REQ-061`: When a distributed control-plane operation fails outside a
documented provider protocol, the control-plane owner shall return an
owner-defined error through the approved seam-12 contract.

`TOP-REQ-062`: The control-plane boundary shall not start an authoring owner
Agent or Plugin runtime as implicit distributed authority.

## Public contract

The implemented core surface remains the local component contract:

| Role | Current public entry | Meaning |
| --- | --- | --- |
| Static authoring | `Jido.Topology`, DSL, Builder, Codec | Validated local definition; no processes |
| Pure plan | `Jido.Topology.instantiate/2` | Validated input and stable local plan |
| Local activation | `Jido.Topology.Controller.start_link/1` | One fixed target on one Jido instance |
| Local readiness | `await_ready/2`, `status/2` | Current local pass and component state |
| Local repair | `reconcile/2` | Repair the same target; not an update |
| Local lookup | `whereis_agent/3`, `whereis_bus/2` | Replaceable local handles |

The target does not add a required control plane to Jido core. An ecosystem
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

## Downstream guarantees

| Consumer seam | Guaranteed contract after approval |
| --- | --- |
| 13 Observability | Control-plane transitions have bounded semantic facts and no Agent state or private handles. |
| 99 Delivery | Each distributed claim has provider, failure, partition, compatibility, and acceptance evidence. |
| Ecosystem control plane | Public Jido local activation and persistence components stay distinct from membership and authority policy. |
| Host application | A control plane is optional and can be selected without changing core Agent semantics. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `TOP-DEC-001` | Where does distributed control-plane code live? | In an optional application or focused ecosystem package, not Jido core. | The Bright Line stays local. |
| `TOP-DEC-002` | What happens to static local Topology? | Keep its current core API and fixed-target repair meaning. | Existing users keep a supported component. |
| `TOP-DEC-003` | What proves exclusive ownership? | A provider-issued increasing epoch enforced at every protected commit. | Lease and Registry presence are not enough. |
| `TOP-DEC-004` | Are time-limited leases required? | No. Permit them as one authority-provider mechanism, but always require fencing for an exclusive claim. | The design stays provider-neutral. |
| `TOP-DEC-005` | What is membership authority? | Advisory placement input only. | Membership failure cannot grant ownership. |
| `TOP-DEC-006` | How are placement ties resolved? | Require deterministic provider policy and an explanation, but do not select an algorithm here. | Tests can repeat a decision without fixing product policy. |
| `TOP-DEC-007` | How does handoff recover state? | Restore through the normal durable Agent record. Do not copy checkpoints in the control plane. | Persistence meaning stays in seam 07. |
| `TOP-DEC-008` | What is the network-partition rule? | Reject new mutations when current authority cannot be confirmed. | Safety takes priority over write availability. |
| `TOP-DEC-009` | Which operator roles are in the contract? | Preview, cordon, uncordon, drain, move, rebalance, suspend, resume, and status. | Product UI remains outside this seam. |
| `TOP-DEC-010` | Does an owner Agent become the control plane? | No. Keep authoring helpers, but do not grant implicit live or distributed authority. | Plugin and Agent state do not become cluster coordination. |
| `TOP-DEC-011` | Is live local target replacement part of this approval? | No. Keep it as a separate later design and acceptance pass. | Distributed placement does not hide an unimplemented local upgrade API. |
