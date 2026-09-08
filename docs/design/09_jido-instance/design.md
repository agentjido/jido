> Target seam design. This document is pending approval.

# Jido instance design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. Code defines current behavior until an approved target is
implemented.

## Scope and owner

- Owner: `Jido`, generated modules that use `Jido`, and the local Jido instance
  supervision boundary.
- In scope: instance startup, local service names, configuration resolution,
  namespace binding, local Agent Ref resolution, Agent Server publication,
  lifecycle facade policy, local inspection, and persistence default selection.
- Out of scope: Agent construction meaning, Turn selection, Plugin facet data,
  commit meaning, persistence records and adapter operations, Agent Server
  private state, Signal transport, placement, cluster authority, Topology
  definitions, live Topology control, and application architecture.
- Adjacent owners: seam 03 owns Agent Ref fields. Seam 07 owns durable records
  and adapter results. Seam 08 owns Agent Server lifecycle semantics. Seams 10
  and 11 own runtime topology and its control plane. Seam 12 owns public errors.

## Model

One Jido instance is one local OTP supervision and API boundary inside an
application. The application starts it in its supervision tree. The instance
does not become the root of that application.

```text
Application Supervisor
└── Jido instance                     local Supervisor and facade
    ├── Task Supervisor               bounded instance execution work
    ├── Registry                      local unique Agent and runtime names
    ├── Runtime Store                 in-instance nondurable coordination
    ├── Spawn Registry                local child-spawn coordination
    └── Agent Dynamic Supervisor      Agent Servers and current Plugin wrappers
```

The recommended first alignment stage keeps this implemented tree and its
`:one_for_one` strategy. A later change to failure coupling or Plugin placement
needs an owner-seam decision and failure-injection proof. This seam does not
redefine Agent Server ownership of Plugin runtimes.

The instance has two separate identities:

| Value | Meaning |
| --- | --- |
| Local instance name | An atom used for the Supervisor and derived local service names. |
| Stable namespace | An optional nonempty binary used to make Agent Refs. It is not a process name or location. |

An instance without a stable namespace stays valid for current ID and PID
operations. Ref-first operations require a namespace. One exact namespace can
have no more than one live local binding on one Erlang node. This is a local
collision check. It is not a cluster directory or authority grant.

The instance facade performs this sequence for a Ref-first operation:

```text
validated Ref
  -> require the instance namespace to match
  -> resolve the complete Ref in the local Registry
  -> reject a missing or dead handle
  -> call the public Agent Server operation
  -> preserve the operation's defined result meaning
```

The instance does not route the Signal to an executable and does not dispatch
to another node. It resolves local identity. Agent Server and Turn seams keep
their existing semantic ownership.

## Requirements

Each identifier is stable. EARS syntax does not grant approval.

### Public role and application composition

`INST-REQ-001`: The Jido instance shall expose a standard OTP child
specification and start function.

`INST-REQ-002`: When an application starts a Jido instance as a supervised
child, the Jido instance shall remain below the application-owned Supervisor.

`INST-REQ-003`: The Jido instance shall provide a public local facade for Agent
Server startup, lifecycle, control, and inspection.

`INST-REQ-004`: The Jido instance shall keep Agent domain state outside its
Supervisor state and configuration.

`INST-REQ-005`: The Jido package application shall not start a required global
Jido instance for application Agents.

### Configuration and identity binding

`INST-REQ-006`: When a module uses `Jido`, the instance authoring boundary
shall require one `otp_app` atom.

`INST-REQ-007`: When a generated instance resolves runtime configuration, it
shall merge `config otp_app, InstanceModule` before explicit startup options.

`INST-REQ-008`: If instance startup input is not a keyword list, then the Jido
instance shall fail before it starts an instance child.

`INST-REQ-009`: If an instance-owned configuration value is invalid, then the
Jido instance shall fail before it starts an instance child.

`INST-REQ-010`: Where stable Ref operations are enabled, the Jido instance
shall require one nonempty binary namespace.

`INST-REQ-011`: If a second live local instance binds the same exact namespace,
then the Jido instance shall fail the second binding before successful startup.

`INST-REQ-012`: When a Jido instance binds a namespace, it shall keep that
namespace independent of the instance module, Supervisor name, PID, and node.

`INST-REQ-013`: When the instance facade creates an Agent Ref, it shall use its
bound namespace and preserve the supplied partition and Agent ID under the
seam-03 Ref contract.

### Supervision, registries, and isolation

`INST-REQ-014`: When a Jido instance starts, it shall start one Task Supervisor,
one unique-key Registry, one Runtime Store, one Spawn Registry, and one Agent
Dynamic Supervisor.

`INST-REQ-015`: While the first alignment stage is active, the Jido instance
shall supervise its standard children with `:one_for_one` strategy.

`INST-REQ-016`: When the Jido instance derives a local service name, it shall
derive it from the local instance name and not from the stable namespace.

`INST-REQ-017`: When the local Registry accepts an Agent registration, it shall
permit no more than one live entry for the exact local Agent key.

`INST-REQ-018`: When two local instances use different local names, each Jido
instance shall use separate Registry, Runtime Store, Spawn Registry, Task
Supervisor, and Agent Supervisor names.

`INST-REQ-019`: While a Jido instance remains live, when its Runtime Store
worker restarts, the instance-owned runtime table shall retain its entries.

`INST-REQ-020`: When a complete Jido instance stops, the Jido instance shall
remove its nondurable Runtime Store data.

`INST-REQ-021`: Where `max_tasks` is configured, the Jido instance shall apply
that value only as the Task Supervisor child limit.

`INST-REQ-022`: When an adapter needs a database, Redis connection, or other
external client process, the Jido instance shall not start that process as an
implicit standard child.

### Agent Server lifecycle and Ref resolution

`INST-REQ-023`: When the current `start_agent` compatibility path succeeds, the
instance facade shall return the started Agent Server PID.

`INST-REQ-024`: When the instance facade starts an Agent Server, it shall make
the instance Agent Dynamic Supervisor the OTP link owner instead of the
original caller.

`INST-REQ-025`: If startup targets an existing live local Agent key, then the
instance facade shall return an error and preserve the existing Agent Server.

`INST-REQ-026`: While current compatibility APIs remain supported, the instance
facade shall keep ID, PID, Server-reference, partition, hibernate, thaw, list,
count, and parent-binding operations.

`INST-REQ-027`: Where a stable namespace is configured, the instance facade
shall provide additive Ref-first startup, activation, command, control,
lifecycle, and inspection operations.

`INST-REQ-028`: If a Ref namespace differs from the instance namespace, then
the instance facade shall return an owner-defined error without calling an
Agent Server.

`INST-REQ-029`: When a Ref-first operation starts, the instance facade shall
resolve the current local Agent Server handle for the complete Ref at that
operation.

`INST-REQ-030`: If local Ref resolution finds no live Agent Server, then the
instance facade shall return the owner-defined not-found result without
starting or routing an Agent implicitly.

`INST-REQ-031`: While no approved migration removes public Agent Server
operations, the Jido instance shall keep those PID and name operations
supported beside its Ref-first facade.

### Command, routing, and dispatch boundaries

`INST-REQ-032`: When a Ref-first synchronous command succeeds, the instance
facade shall preserve the Agent Server meaning that success confirms commit
but not Directive settlement or external business completion.

`INST-REQ-033`: When a Ref-first cast returns `:ok`, the instance facade shall
mean only that it sent the Signal to the resolved local Server handle.

`INST-REQ-034`: When Ref-first asynchronous request functions are used, the
instance facade shall preserve the documented OTP asynchronous-request
envelope.

`INST-REQ-035`: When the instance facade receives a Signal operation, it shall
not select an Action or Flow or change the source Signal.

`INST-REQ-036`: When an Agent Server emits an outbound Signal, the Jido
instance shall not replace the Agent Server or `jido_signal` dispatch result.

### Callbacks and extension points

`INST-REQ-037`: While `config/1` remains overridable, the generated instance
module shall use its returned keyword list as the input to instance validation.

`INST-REQ-038`: If an overridden `config/1` returns a non-keyword value, then
the Jido instance shall fail before it starts an instance child.

`INST-REQ-039`: When Agent activation, restore, stop, crash, Turn commit, or
Plugin runtime health changes, the Jido instance shall not call an instance
lifecycle callback.

`INST-REQ-040`: While no instance-child callback is approved, the Jido instance
shall require application-owned services to enter an application supervision
tree through standard OTP composition.

### Persistence configuration and lifecycle delegation

`INST-REQ-041`: Where a generated instance declares persistence, the Jido
instance shall use that declaration as the default persistence source for its
Agent Servers.

`INST-REQ-042`: When Agent Server startup supplies an explicit persistence
source or explicit disablement, the instance facade shall give that choice
precedence over the instance default.

`INST-REQ-043`: If the instance persistence default is invalid, then the Jido
instance shall fail before it starts an instance child.

`INST-REQ-044`: When the instance facade hibernates or activates a durable
Agent, it shall delegate record, restore, readiness, and write-authority meaning
to seams 07 and 08 without changing those results.

`INST-REQ-045`: Where the approved persistence contract supports durable
logical deletion, the instance facade shall expose that operation only through
the seam-07 tombstone contract.

### Status, errors, and limits

`INST-REQ-046`: When local Agent listing or counting runs, the instance facade
shall include only live Agent Server registrations in the selected instance and
partition.

`INST-REQ-047`: When local Agent lookup finds a dead Registry handle, the
instance facade shall return `nil` on the current compatibility lookup path.

`INST-REQ-048`: When a Ref-first inspection operation resolves a live Server,
the instance facade shall delegate Agent, Plugin state, status, snapshot,
children, readiness, and debug inspection to supported Agent Server operations.

`INST-REQ-049`: While current debug controls remain supported, the generated
instance module shall keep instance debug status and bounded Agent event access.

`INST-REQ-050`: If a public instance operation fails outside a documented OTP
or compatibility protocol result, then the instance facade shall return the
owner-defined seam-12 error.

`INST-REQ-051`: If a PID or Server reference does not belong to the selected
instance and partition, then the instance facade shall reject the operation
without changing that Server.

`INST-REQ-052`: When the facade accepts a caller wait limit, it shall keep that
limit separate from Agent Server Turn, Directive, readiness, persistence,
idle, and postponed-event limits.

`INST-REQ-053`: Where `max_tasks` is finite, the Jido instance shall not claim
that this value bounds the Agent Server mailbox or postponed-event count.

### Runtime topology and control-plane limits

`INST-REQ-054`: The Jido instance shall not provide cluster discovery,
placement, rebalance, failover, transport, lease, or fencing authority.

`INST-REQ-055`: When a namespace is bound locally, the Jido instance shall not
treat that binding as proof of Agent location or exclusive write authority on
another node.

`INST-REQ-056`: If a Ref-first local operation names an Agent that is not live
in the selected local instance, then the Jido instance shall not forward the
operation through a Topology controller or transport without an explicit
owner-seam API.

## Public contract

### Current compatibility surface

The target keeps these implemented roles until separate migration approval:

| Role | Current entries |
| --- | --- |
| Instance OTP | `child_spec/1`, `start_link/1`, plain `Jido.start/1`, `Jido.stop/1` |
| Config | generated `config/1`, `__otp_app__/0`, `__jido_persistence__/0` |
| Lifecycle | `start_agent`, `stop_agent`, `whereis_agent`, `list_agents`, `agent_count`, `hibernate`, `thaw` |
| Relationship lookup | `agent_parent_binding` |
| Local names | Registry, Task Supervisor, Runtime Store, and Agent Supervisor name helpers |
| Debug | `debug`, `debug_status`, and `recent` |

Current direct `Jido.AgentServer` command, control, lifecycle, and inspection
functions also remain public. A Ref facade is additive and does not make them
private by declaration.

### Recommended Ref-first facade roles

Exact function names and arities remain an open API naming decision. The
approved surface must cover these roles without private Server access:

| Role | Required capability |
| --- | --- |
| Identity | Build and validate a Ref in the instance namespace. |
| Publication | Start supplied Agent data or activate known durable identity. |
| Command | Synchronous call, best-effort cast, and OTP asynchronous request. |
| Control | Cancel eligible work and target one Turn ID. |
| Lifecycle | Stop, hibernate, activate, attach, detach, touch, and approved durable delete. |
| Inspection | Local lookup, Agent, Plugin state, status, snapshot, children, readiness, list, count, and debug data. |

`whereis_agent` keeps its current PID-or-`nil` compatibility meaning. A future
Ref overload or separate local resolver must still identify its PID as a
replaceable local handle.

### Configuration precedence

The recommended resolution order is:

1. compile-time instance declaration for `otp_app` and the persistence default;
2. `config otp_app, InstanceModule` runtime values;
3. explicit `child_spec/1` or `start_link/1` options;
4. explicit per-Agent options for Agent Server-owned values.

An explicit per-Agent persistence source or disablement wins over the instance
default. Observability keeps its own approved resolution rules. The instance
does not combine every package option into one new public struct in this stage.

### Extension contract

The target keeps overridable `config/1`. It adds no `children/1`,
`configure/1`, `admit_agent/2`, `after_start`, `before_stop`, `agent_started`,
or `agent_stopped` callback. Applications can add sibling or nested supervised
services. Telemetry observes lifecycle. Plugins own Agent and Agent Server
extension behavior. Directives own post-commit work.

## Invariants

- `INST-INV-001`: One local instance name identifies one live instance
  Supervisor and one derived set of local service names.
- `INST-INV-002`: A stable namespace is Agent identity input, not runtime
  location or write authority.
- `INST-INV-003`: A Ref-first operation resolves a current local handle before
  it calls an Agent Server.
- `INST-INV-004`: The instance facade does not redefine Agent Server result
  meaning.
- `INST-INV-005`: A complete instance stop removes nondurable instance state.
- `INST-INV-006`: External service processes remain application-owned.
- `INST-INV-007`: Current ID and PID APIs remain supported until an approved
  compatibility gate removes them.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 10 Runtime topology | One local instance can start and resolve Agent Servers. Namespace does not provide placement or authority. |
| 11 Topology control plane | Instance lifecycle functions are callable components, not a desired-state controller. |
| 13 Observability | Instance and Agent Server debug and status compatibility paths remain available during migration. |
| 99 Delivery | Ref-first migration cannot remove supported ID, PID, partition, or direct Server paths without a separate gate. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `INST-DEC-001` | What is the instance role? | Keep an application-owned local Supervisor and facade. | Jido stays a composable library. |
| `INST-DEC-002` | Which first-stage supervision tree applies? | Keep the implemented five children and `:one_for_one`. | Alignment can begin without an unproved restart redesign. |
| `INST-DEC-003` | How is namespace bound? | Make it optional for compatibility, exact, and unique among live local bindings on one node. | Ref work can start without breaking plain instances. |
| `INST-DEC-004` | What is the Ref API shape? | Add one complete Ref-first family after a focused naming review. | Callers get one local resolution policy without removing direct Server calls. |
| `INST-DEC-005` | Which persistence precedence applies? | Keep explicit per-Agent selection or disablement above the instance default. | Current use cases and seam-07 compatibility stay valid. |
| `INST-DEC-006` | Which instance callbacks exist? | Keep only overridable `config/1` now. | New callback authority waits for a proved use case. |
| `INST-DEC-007` | Does the instance resolve remote Agents? | No. Keep this facade local. | Topology and transport owners can add explicit higher-level APIs. |
