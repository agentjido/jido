> Target seam design. This document is pending approval.

# Package and extension boundaries design

All requirements and decisions in this document are recommended targets. The
Overview is a draft prerequisite with `Pending approval` status. This document
does not make the Overview approved.

## Scope and owner

- Owner: the Jido package boundary and public extension policy.
- In scope: package ownership, dependency direction, extension selection,
  public boundary rules, compatibility rules, and cross-package release gates.
- Out of scope: exact public value fields, callback signatures, storage record
  formats, lifecycle state machines, error codes, and implementation plans.
- Lower-layer owners: `jido_action` owns Actions, Instructions, Flows, and
  in-memory execution. `jido_signal` owns Signals, serialization, routing,
  dispatch, and the local Signal bus.
- Application owner: the developer owns application architecture, external
  clients, domain policy, deployment, and operational policy.

## Ownership model

| Owner | Target responsibility | Excluded responsibility |
| --- | --- | --- |
| `jido_action` | Actions, Instructions, Flows, executable validation, in-memory execution, execution timeout, and execution telemetry | Agent state commit, durable orchestration, Agent lifecycle, and transport |
| `jido_signal` | Signal envelope, serialization, ordered route matching, dispatch adapters, and local Signal bus | Agent Turn selection, Agent commit, placement, and durable Agent state |
| `jido` | Agent meaning, Turn use of lower-layer contracts, Plugin composition, candidate assembly, live commit, Directives, local Agent Server and instance runtime, persistence record meaning, static local Topology, public errors, and semantic Agent observation | General workflow recovery, cluster policy, transport gateways, AI-provider policy, browser sessions, and application architecture |
| Integration packages | Focused capabilities such as AI policy, browser automation, storage providers, recovery services, placement policy, and transport | Changes to Jido semantics or private Jido access |
| Host application | Ordinary composition, external resource supervision, authorization, business transactions, deployment, and product policy | Redefinition of public package contracts |

The target dependency direction is:

```text
jido_action     jido_signal
      \           /
            jido
              |
  focused integration packages
              |
       host application
```

An integration package can depend directly on a lower package when it uses
that lower package's public contract. It does not need Jido as a transit path.
`jido_action` and `jido_signal` stay independent of `jido`.

### Jido core boundary

Jido is a complete local Agent runtime. It is not a hosted service, a
deployment system, a cluster control plane, or a durable workflow platform.
Core includes a contract only when the contract protects shared Agent
semantics or runtime safety and cannot be implemented safely through current
public APIs.

Static local Topology and explicit start of an owned child on a known Erlang
node are Jido runtime contracts. Cluster membership, automatic placement,
rebalance, ownership claims, and failover policy are outside Jido.

Persistence record meaning, checkpoint validation, revision policy, and the
effect of a persistence result on Agent commit stay in Jido. A byte adapter
owns storage operations. The host application owns and supervises the database,
Redis, object-store, or other external client.

### Focused ecosystem boundaries

The following names describe capability groups. They do not reserve a package
name or claim that a package API is available.

| Capability group | May own | Must not own |
| --- | --- | --- |
| Durable services, with `jido_durable` as a working name | Production storage integrations, record catalogs and scans, recovery controllers, claims and fencing, leases, indeterminate-write reconciliation, tombstone cleanup, migration tools, durable request receipts, result lookup, history, compaction, and retention | Agent candidate assembly, core commit order, Plugin state writes, or Signal envelope meaning |
| Cluster services, with `jido_cluster` as a working name | Membership, node, a distributed location directory, placement, rebalance, failover coordination, load, and capacity | Durable write authority from a Registry result or Agent state persistence |
| Transport services, with `jido_fabric` as a working name | Cross-namespace delivery, external reference encoding, request correlation, admission, backpressure, delivery timeout, gateways, authentication, tenancy, store-and-forward, and durable inboxes | Inspection of Agent checkpoints or commits, or replacement of local Turn and commit rules |
| `jido_ai` | Model integration, AI behavior, tools, request orchestration, retry and quota policy, and AI-specific observation | Core Agent semantics or private Agent Server access |
| `jido_browser` | Browser sessions, browser adapters, and browser Actions | Browser concerns in Jido core |

A durable inbox is separate from Agent persistence. A location directory is
separate from storage authority. A capability that promises recoverable work
owns its pending intent, stable operation IDs, acknowledgement, and recovery
policy. Ordinary Directives do not become a universal durable outbox.

## Extension selection rules

Each category grants different authority.

| Need | Select | Boundary |
| --- | --- | --- |
| Add an application facade, policy, supervision, or multi-component coordination | Ordinary Elixir composition | Wrap public modules and use standard OTP |
| Define executable computation | Action or Flow | Implement in `jido_action`; Jido consumes it through `Jido.Exec` |
| Define, route, serialize, or deliver an event | Signal contract | Implement in `jido_signal` |
| Add a reusable capability at an Agent or Agent Server lifecycle point | Plugin | Use declared Plugin state, callbacks, Directives, and optional runtime only |
| Replace one external infrastructure operation | Adapter | Implement the narrow adapter owned by that package |
| Add static DSL syntax | Authoring extension | Lower to the canonical Agent or Topology value before runtime |
| Request runtime-owned work after commit | Directive | Return a typed Directive through the Turn result |
| Observe runtime behavior | Telemetry handler | Consume bounded events without execution authority |

The package that owns a contract also owns its adapter behavior. A
`Jido.Persistence.Adapter`, a `Jido.Signal.Dispatch.Adapter`, and a browser
adapter are separate contracts. Jido does not define one universal adapter.

A Plugin is not an adapter, middleware layer, authoring extension, Action,
Directive, or Telemetry handler. A Provider is not a generic hook. If a future
instance infrastructure boundary uses the term Provider, its design must name
one fixed lifecycle and one fixed authority.

## Public boundary rules

An ecosystem package uses documented public modules. It does not:

- read or change private Agent Server state;
- send private Agent Server messages;
- construct a generated supervisor or Registry name as a required dependency;
- change candidate Agent or Plugin state outside the Turn evaluator;
- dispatch runtime-owned work before the related commit;
- treat a PID or OTP name as durable Agent identity.

If an integration cannot work without one of these actions, the owner seam
evaluates a small public core contract. The proposal must name the protected
invariant, owner, authority, input, output, error, and acceptance test. Core
does not expose a private implementation only to make an integration work.

Public Jido modules remain suitable for direct calls, wrappers, standard OTP
child specifications, and application supervision. A public contract has
module documentation, input validation, stable result meaning, and executable
tests. An integration package does not use `@doc false` modules or functions.

Current supported APIs stay available unless an owner seam approves a staged
migration. This rule covers direct and DSL Agent authoring, Builder, Codec,
Agent and Topology authoring extensions, custom routing, complete checkpoint
callbacks, Plugins, Directives, `spawn_fun`, owned children, explicit known-node
child placement, public PID-based Agent Server operations, Jido instance
lifecycle and name helpers, per-Agent persistence selection, persistence
adapters, static local Topology, legacy and semantic telemetry, `Jido.Observe`,
tracing, and debug paths.

A Ref-first identity or instance command facade is additive before any
restriction of ID, PID, or generated-name APIs. The identity owner defines
storage-key migration and collision handling. This seam does not define the
Agent Ref value.

Migration ownership stays separate:

| Migration | Owner |
| --- | --- |
| Core persistence record format | Jido persistence seam |
| Agent domain-state meaning | Agent module or host application |
| Plugin-owned state meaning | Owning Plugin |
| Backend schema and physical data movement | Adapter package and host application |
| Cross-package version rollout | 99 Delivery and each package release owner |

## Requirements

These EARS requirements define the recommended target. Approval status remains
separate from requirement syntax.

### Package ownership and dependency direction

`PKG-REQ-001`: The Jido core package shall provide local Agent semantics and
runtime components without a required hosted or global runtime.

`PKG-REQ-002`: The Jido core package shall keep general durable recovery,
cluster policy, transport gateways, AI-provider policy, and browser sessions
outside the core package.

`PKG-REQ-003`: When Jido runs an Action, Instruction, or Flow, the Jido package
shall use the public `jido_action` execution contract.

`PKG-REQ-004`: When Jido handles a Signal, route, dispatch target, or local
Signal bus, the Jido package shall use the public `jido_signal` contract.

`PKG-REQ-005`: The `jido_action` and `jido_signal` packages shall remain
independent of the `jido` package.

`PKG-REQ-006`: When an integration package uses Jido behavior, the integration
package shall use only public contracts from the package that owns that
behavior.

### Distinct extension categories

`PKG-REQ-007`: When application code adds a facade, policy, or supervision
above Jido, the application shall use ordinary Elixir and OTP composition.

`PKG-REQ-008`: When an extension defines executable computation, the extension
shall use an Action or Flow owned by `jido_action`.

`PKG-REQ-009`: When an extension defines an event envelope, route, dispatch, or
bus behavior, the extension shall use the owning `jido_signal` contract.

`PKG-REQ-010`: When a reusable capability participates in an Agent or Agent
Server lifecycle boundary, the capability shall use the owning Plugin
contract.

`PKG-REQ-011`: When an external service replaces one infrastructure operation,
the integration shall use the narrow adapter owned by that package.

`PKG-REQ-012`: When an extension adds Agent or Topology syntax, the authoring
extension shall lower its declarations to the canonical value before runtime
activation.

`PKG-REQ-013`: When a Turn returns runtime-owned work, the Jido runtime shall
interpret its typed Directives only after the related live commit.

`PKG-REQ-014`: Where recoverable work is required, the capability owner shall
store portable work intent outside the ordinary Directive delivery guarantee.

`PKG-REQ-015`: When a Telemetry handler observes a Jido event, the handler
shall have no authority to change the Agent result, commit result, or runtime
outcome.

`PKG-REQ-016`: The Jido core package shall not provide a generic runtime hook
or universal adapter that combines distinct extension categories.

### Extension and public boundary tests

`PKG-REQ-017`: When ordinary public composition cannot protect a Jido semantic
invariant, the owning seam shall evaluate one narrow public core contract.

`PKG-REQ-018`: An external package shall not read or change private Agent
Server state.

`PKG-REQ-019`: An external package shall not send private Agent Server
messages.

`PKG-REQ-020`: An external package shall not require a generated Jido
supervisor or Registry name.

`PKG-REQ-021`: An external package shall not change candidate Agent or Plugin
state outside the Turn evaluator.

`PKG-REQ-022`: An external package shall not dispatch runtime-owned
Directive work before the related commit.

`PKG-REQ-023`: An external package shall not treat a PID or OTP name as
durable Agent identity.

`PKG-REQ-024`: When Jido publishes a package extension contract, the contract
owner shall provide public module documentation and executable acceptance
tests.

### Infrastructure and service boundaries

`PKG-REQ-025`: Where Agent persistence is configured, the Jido persistence
adapter shall store binary keys and values with atomic compare-and-swap.

`PKG-REQ-026`: Where Agent persistence is configured, the Jido package shall
own checkpoint validation, record meaning, revision policy, and commit response
to storage results.

`PKG-REQ-027`: Where an adapter uses an external client process, the host
application shall supervise that client outside Jido.

`PKG-REQ-028`: The Jido core package shall retain static local Topology
definition, activation, readiness, and repair as core contracts.

`PKG-REQ-029`: When Jido starts an owned child on an explicit Erlang node, the
Jido runtime shall treat node selection as explicit placement and not as
cluster policy.

`PKG-REQ-030`: When a cluster integration selects placement or failover, the
cluster integration shall use public Jido activation and persistence
boundaries.

`PKG-REQ-031`: When a transport integration delivers work to an Agent, the
transport integration shall deliver a Signal through a public Jido boundary.

`PKG-REQ-032`: A transport integration shall not inspect an Agent checkpoint
or commit value.

`PKG-REQ-033`: When `jido_ai` or `jido_browser` integrates with Jido V3, the
integration shall use the same public Action, Signal, Plugin, Directive, and
instance contracts as another ecosystem package.

### Compatibility, migration, and release

`PKG-REQ-034`: While an owner seam has not approved and proved a staged
migration, the Jido package shall preserve its supported public extension
contracts.

`PKG-REQ-035`: While persistence authority remains undecided, the Jido package
shall preserve instance persistence defaults and supported per-Agent
persistence selection.

`PKG-REQ-036`: When a stored format changes, the migration design shall assign
separate owners to record format, Agent state, Plugin state, and backend
storage migration.

`PKG-REQ-037`: Before an ecosystem package claims Jido V3 compatibility, its
release owner shall prove one explicit compatible V3 package set through
public contracts.

`PKG-REQ-038`: Before Jido is published, the Jido release owner shall replace
development path dependencies with intended release sources or document an
approved source exception.

`PKG-REQ-039`: If a future package lacks a released public API and acceptance
evidence, then Jido documentation shall describe its capability list as a
proposal and not as available behavior.

## Invariants

- `PKG-INV-001`: Dependency direction is
  `jido_action` and `jido_signal` to Jido to focused integrations to the host
  application.
- `PKG-INV-002`: One contract has one package owner.
- `PKG-INV-003`: Actions, Signals, Plugins, adapters, authoring extensions,
  Directives, Telemetry, and ordinary composition grant different authority.
- `PKG-INV-004`: An ecosystem package does not depend on private Jido state,
  messages, or generated runtime names.
- `PKG-INV-005`: An extension cannot bypass candidate evaluation, live commit,
  or post-commit Directive order.
- `PKG-INV-006`: Storage authority, runtime location, and durable Agent
  identity are separate.
- `PKG-INV-007`: A durable inbox, a cluster directory, and Agent persistence
  are separate services.
- `PKG-INV-008`: A supported public API remains until an approved staged
  migration has replacement proof.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam or package | Guaranteed boundary |
| --- | --- |
| 01 Agent and 04 Turn evaluation | Jido consumes public Action and Signal contracts and keeps candidate assembly in Jido. |
| 02 Agent authoring and 11 Topology control plane | Authoring extensions lower to canonical values and do not add a runtime. |
| 03 Agent identity | PID, runtime name, and durable identity stay separate; current APIs remain during migration. |
| 05 Plugins | Plugins remain a lifecycle capability, not a universal extension type. |
| 06 Commit and effects | Actions can perform I/O before commit; runtime-owned Directives run after commit. |
| 07 Persistence and 09 Jido instance | Jido owns record meaning; adapters own byte storage; external clients stay application-owned. |
| 10 Runtime topology | Static local Topology and explicit known-node children stay in core; cluster policy stays outside. |
| 12 Errors and contracts | Every exported extension entry has one owner, documented results, and a compatibility rule. |
| 13 Observability | Telemetry observes behavior and cannot change it. |
| `jido_ai` and `jido_browser` | Integration uses public V3 package contracts without private Jido access. |
| 99 Delivery | Compatibility claims require one tested package set and publishable dependency sources. |

## Open design decisions

All recommendations are pending approval.

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `PKG-DEC-001` | Is Jido a local library or a general platform? | Keep it a complete local Agent library. | Durable, cluster, transport, AI, browser, and product policy stay outside. |
| `PKG-DEC-002` | What is the default extension method? | Use ordinary Elixir composition. | Plugins and adapters keep narrow authority. |
| `PKG-DEC-003` | Where do production storage adapters live? | Keep the adapter contract and record meaning in Jido; decide each provider implementation from dependency and release needs. | Existing ETS, File, and Redis APIs stay supported until a staged move is approved. |
| `PKG-DEC-004` | Can one Agent override instance persistence? | Preserve the current option for V3 unless seams 07 and 09 approve a migration. | Existing callers do not lose storage selection without replacement proof. |
| `PKG-DEC-005` | Do PID commands and generated-name helpers become private? | No immediate change. Add Ref-first and instance facades first, then review deprecation. | Current application and integration code has a staged path. |
| `PKG-DEC-006` | Is static Topology permanent core scope? | Yes, for local definition, activation, readiness, and repair. | Cluster placement and failover remain separate. |
| `PKG-DEC-007` | Are future package names and APIs fixed? | No. Keep capability groups, but require package-specific design and proof. | Documents do not claim unavailable APIs. |
| `PKG-DEC-008` | Who owns stored-data migration? | Use separate core-record, Agent-state, Plugin-state, and backend-storage owners. | A version change cannot hide application or operator work. |
| `PKG-DEC-009` | What proves an ecosystem boundary? | A public-only fixture plus one explicit compatible V3 package matrix. | Internal core tests cannot be the only release evidence. |
