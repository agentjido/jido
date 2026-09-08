> Target seam design. This document is pending approval.

# Core model, shared terms, and invariants design

All requirements and decisions in this document are recommended targets. The
[design review index](../README.md#document-review-status) is the source of
truth for approval. It does not approve any item in this document.

## Scope and owner

- Owner: the shared Jido Agent model and cross-system boundaries.
- In scope: the common execution model, shared terms, value roles, the Jido and
  OTP boundary, cross-system invariants, owner-seam assignments, and dependency
  gates.
- Out of scope: exact struct fields, callback signatures, error codes, storage
  operations, supervision layouts, and topology update protocols.
- Lower-layer owners: `jido_action` owns Actions, Instructions, Flows, and
  `Jido.Exec`. `jido_signal` owns the Signal envelope, ordered route matching,
  dispatch, and the local Signal bus.
- Application owner: the developer owns application architecture, domain
  policy, external clients, deployment, cluster policy, transport gateways,
  durable business workflows, AI-provider policy, and user interfaces.

## Model

Jido is an Elixir library and SDK. It is not a hosted service, application
framework, deployment system, or control plane. It supplies reusable Agent
semantics and local runtime components. The developer owns the system that
uses them.

The shared direct-evaluation model is:

```text
Agent definition
  -> Agent instance and source Signal
  -> one Turn with one fixed Action or Flow
  -> one validated candidate Agent and Directive batch
  -> evaluation return
```

Direct evaluation stops at the evaluation return. It does not commit state or
handle Directives.

The shared live model is:

```text
source Signal
  -> live admission
  -> first route match from the source Signal
  -> one fixed Action or Flow
  -> isolated Plugin preparation
  -> executable work through Jido.Exec
  -> ordered Plugin contributions
  -> one validated candidate Agent and Directive batch
  -> required persistence
  -> one live commit and state-version increment
  -> live result
  -> ordered Directive handling
  -> terminal Turn Outcome
```

Admission can accept, reject, or add bounded context. It cannot change the
selected executable. Seams 04 and 05 own the exact effective-Signal and Plugin
input contracts.

Jido and OTP have separate responsibilities:

| Concern | Jido owns | OTP owns |
| --- | --- | --- |
| Input | Signal meaning and Agent admission policy. | Mailbox delivery and ordering. |
| Execution | Turn selection, candidate assembly, and commit policy. | Processes, tasks, and scheduling. |
| State | Immutable Agent values and state-version rules. | Live process-state ownership. |
| Effects | Executable effect boundary and post-commit Directives. | I/O, timers, and resource processes. |
| Failure | Domain, validation, and public Jido errors. | Exits, monitors, restart, and shutdown. |
| Lifecycle | Logical Agent policy and durable record rules. | Supervision mechanics. |

## Requirements

These EARS requirements define the recommended target. Their identifiers are
stable. Approval status remains separate.

### Library boundary and composition

`OVR-REQ-001`: The Jido core library shall provide reusable Agent semantics and
local runtime components without a required global or hosted runtime.

`OVR-REQ-002`: The Jido core library shall leave application architecture,
deployment, external service clients, and operational policy under developer
control.

`OVR-REQ-003`: The Jido public API shall support direct calls, ordinary Elixir
wrappers, standard tagged results, OTP child specifications, supervision, and
application configuration.

`OVR-REQ-004`: When Jido uses `jido_action` or `jido_signal`, the Jido core
library shall interact with them only through their public contracts.

`OVR-REQ-005`: The Jido core library shall keep Plugin packages, Plugin facets,
adapters, authoring extensions, Directive handlers, and observation handlers as
separate extension categories.

### Agent definition, identity, and restore

`OVR-REQ-006`: The Agent model shall distinguish an immutable static Agent
definition from an immutable Agent instance with identity and state.

`OVR-REQ-007`: The Agent instance shall be an immutable value that contains
identity and complete validated portable state, but no live runtime handle or
executable workflow state.

`OVR-REQ-008`: When an Agent definition comes from a module, DSL, Builder,
Codec, or direct data, the Agent authoring boundary shall produce the same
normalized definition contract.

`OVR-REQ-009`: Where an Agent definition has a module owner, the normalized
Agent definition contract shall contain one positive module-owned definition
revision.

`OVR-REQ-010`: When saved state for a module-authored Agent is restored, the
Agent restore boundary shall check the saved Agent module and definition
revision before the state becomes live.

`OVR-REQ-011`: Where stable Agent identity is used, the Agent identity boundary
shall use one Agent Ref for lookup, persistence, delivery, and placement.

`OVR-REQ-012`: The Agent runtime shall treat a PID or OTP name as a replaceable
runtime handle and not as durable Agent identity.

### Turn and Plugin boundaries

`OVR-REQ-013`: When Jido receives a Signal for a Turn, the Turn evaluator shall
preserve that value as the unchanged source Signal.

`OVR-REQ-014`: When the default Signal Router returns one or more matching
targets, the Turn evaluator shall select its first target before Plugin
preparation.

`OVR-REQ-015`: When the Turn evaluator has selected an executable, Plugin
admission and preparation shall not replace that executable or cause another
route lookup.

`OVR-REQ-016`: Where an Agent declares no Plugins, the Turn evaluator shall
execute the same Agent path without a Plugin dependency.

`OVR-REQ-017`: When direct `Jido.Agent.cmd/3` evaluation succeeds, the Agent
boundary shall return one validated candidate Agent and one Directive list
without a live commit or Directive handling.

`OVR-REQ-018`: When direct and live execution receive the same valid Agent,
Signal, and evaluation options, both paths shall use the same candidate-
evaluation boundary.

`OVR-REQ-019`: While a Turn is in evaluation, the selected Action or Flow shall
be the only writer of Agent domain state.

`OVR-REQ-020`: While a Turn is in evaluation, each stateful Plugin shall
replace at most one complete state entry that it owns.

`OVR-REQ-021`: While Plugin preparation or contribution runs, the Plugin
boundary shall give each Plugin only its declared Agent view, its owned
prepared input, and the Turn Directives that it owns.

`OVR-REQ-022`: When more than one Plugin participates in a Turn, the Plugin
boundary shall run preparation and contribution serially in declaration order.

`OVR-REQ-023`: When executable output and Plugin contributions are available,
the Turn evaluator shall produce one complete validated candidate Agent.

### Commit, effects, and recoverable work

`OVR-REQ-024`: When a live Turn succeeds, the Agent Server shall make the
candidate Agent authoritative at one commit point.

`OVR-REQ-025`: When a live Agent state commit succeeds, the Agent Server shall
increase the state version by one, including when the state value is equal to
the prior value.

`OVR-REQ-026`: If a Turn fails before commit, then the Agent Server shall
preserve the committed Agent and state version.

`OVR-REQ-027`: If an Action or Flow performs external I/O before commit, then
the Jido commit boundary shall not report that external I/O as rolled back.

`OVR-REQ-028`: When a live commit succeeds, the Agent Server shall start its
runtime-owned Directive work after the commit.

`OVR-REQ-029`: If post-commit Directive handling fails, then the Agent Server
shall preserve the committed Agent and state version.

`OVR-REQ-030`: The ordinary Directive contract shall make no general
crash-recovery guarantee.

`OVR-REQ-031`: Where a capability promises recoverable work, the capability
shall save portable work intent and a stable operation ID with the related
business-state change.

`OVR-REQ-032`: Where a capability has saved pending work, when its supervised
worker starts, the capability shall resume that pending work.

`OVR-REQ-033`: When recoverable work completes, the capability shall report
completion through a new Signal and a normal Agent commit.

`OVR-REQ-034`: The Jido core runtime shall not apply a universal durable-outbox
gate to ordinary Directives.

### Persistence and lifecycle

`OVR-REQ-035`: Where persistence is configured, the persistence adapter shall
provide an atomic compare-and-swap operation over binary keys and values.

`OVR-REQ-036`: The persistence adapter shall not own Agent lifecycle policy or
inspect Agent checkpoint meaning.

`OVR-REQ-037`: Where persistence is configured, when a live commit occurs, the
Agent Server shall make the candidate Agent visible only after a confirmed
successful compare-and-swap write.

`OVR-REQ-038`: If a required persistence write is not confirmed, then the Agent
Server shall not start the related Directive batch.

`OVR-REQ-039`: If a persistence write returns an error or an indeterminate
result, then the Agent Server shall remove write authority from that activation
before it admits another Turn.

`OVR-REQ-040`: Where persistence is configured, when a new Agent activation
becomes ready, the Agent runtime shall make provisional Plugin runtimes ready,
write an initial active record at state version zero, and then report Agent
readiness.

`OVR-REQ-041`: Where persistence is configured, when an Agent Server restarts,
the Agent runtime shall load the latest valid durable record before it admits a
Turn.

`OVR-REQ-042`: Where persistence is configured, when normal durable deletion
occurs, the persistence boundary shall write a compare-and-swap tombstone.

`OVR-REQ-043`: When a value enters an Agent checkpoint or persistence record,
the persistence boundary shall reject a PID, port, reference, function,
improper list, or non-byte-aligned bitstring in that value.

`OVR-REQ-044`: Where a nonpersistent Agent Server runs in a named Jido instance,
when that Server restarts abnormally, the Agent runtime shall restore the
latest in-instance runtime checkpoint and its state version.

`OVR-REQ-045`: When the complete named Jido instance stops, the Jido instance
shall remove its nondurable runtime checkpoints.

### Runtime ownership and cancellation

`OVR-REQ-046`: While an Agent activation is live, one Agent Server shall be its
only serialized state and commit owner.

`OVR-REQ-047`: The Jido runtime shall treat Agent Servers as Agent-pool peers
and Plugin runtime hosts as capability resources.

`OVR-REQ-048`: When a Plugin runtime is replaced, the Plugin runtime boundary
shall give it one current committed Plugin state value and the matching Agent
state version.

`OVR-REQ-049`: When a Plugin runtime requests an Agent state change, the Plugin
runtime shall send a Signal through the Agent mailbox.

`OVR-REQ-050`: While a Turn is before commit, the Agent Server shall limit Turn
cancellation to admission and executable evaluation.

`OVR-REQ-051`: While a Turn is committing or handling Directives, the Agent
Server shall reject cancellation through the Turn cancellation contract.

### Public values, errors, and observation

`OVR-REQ-052`: The public-contract boundary shall give each shaped public
success value one documented owner and one purpose.

`OVR-REQ-053`: If a public construction, command, or lifecycle operation fails,
then its owner shall return an owner-defined Splode error unless seam 12 lists
that result as a protocol exception.

`OVR-REQ-054`: When direct `Jido.Agent.cmd/3` evaluates an Agent, the Agent
boundary shall emit no Agent runtime telemetry.

`OVR-REQ-055`: When a live Turn commits, the Agent observation boundary shall
end the live Turn result span at the commit and live-result boundary.

`OVR-REQ-056`: When post-commit Directive work runs, the Agent observation
boundary shall use spans separate from the live Turn result span.

`OVR-REQ-057`: When a live Turn settles, the Agent observation boundary shall
publish one terminal Turn Outcome.

`OVR-REQ-058`: If an observation handler fails, then the Agent observation
boundary shall preserve the defined Agent result and runtime outcome.

`OVR-REQ-059`: When the Agent observation boundary emits semantic telemetry,
it shall exclude Agent state, Plugin state, payloads, caller context, process
handles, and raw error detail from metadata.

### Topology, package scope, and compatibility

`OVR-REQ-060`: The Jido V3 runtime shall support static local Topology
definition, planning, activation, readiness, and repair.

`OVR-REQ-061`: The Topology control plane shall not treat an authoring owner
Agent as live topology authority without an owner-seam contract and executable
proof.

`OVR-REQ-062`: The Jido core library shall keep general durable recovery
services, cluster policy, placement, transport gateways, and durable inboxes
outside the core package.

`OVR-REQ-063`: While an owner seam has not approved and proved a staged
migration, the Jido V3 public API shall preserve DSL and direct authoring,
Builder, Codec, neutral definitions, custom routing, complete checkpoint
callbacks, owned children, public PID APIs, persistence adapters, and local
observation and debug paths.

### Additional shared public rules

`OVR-REQ-064`: Where a live Agent Server uses persistence, the Agent Server
shall perform persistence operations through its owning Jido instance context.

`OVR-REQ-065`: Where a public result uses a raw map, tuple, atom, or OTP control
value, the public-contract owner shall document it as a protocol exception.

`OVR-REQ-066`: When a public entry accepts keyword options, the entry owner
shall validate those options before the operation starts.

## Public and shared contract

This seam defines roles and owners. It does not approve a new struct name or
field set. An owner seam can keep a documented map or tuple when that protocol
is clearer than a struct.

| Value or contract | Shared role | Detailed owner |
| --- | --- | --- |
| Signal | Immutable input envelope. The received value is the source Signal. | `jido_signal`; seams 04 and 05 own Jido use. |
| Agent definition | Static schema, routes, Plugin declarations, metadata, and definition revision. | 01 Agent and 02 Agent authoring |
| Agent instance | Immutable identity and complete portable domain and Plugin state. | 01 Agent |
| Agent Ref | Stable identity, separate from runtime location. | 03 Agent identity, then 07, 09, and 10 |
| Turn | One fixed executable and input for one source Signal. | 04 Turn evaluation |
| Candidate Agent | Complete validated Agent proposed by evaluation. | 01 and 04 |
| State version | Revision that increases once for each successful live commit. | 06 Commit and effects, 08 Agent Server |
| Evaluation return | Direct candidate Agent and Directive list, or an error. It proves no live commit. | 01, 04, and 12 |
| Live result | Tagged live reply at the commit boundary. It is not the Turn Outcome. | 08 and 12 |
| Turn Outcome | Terminal observation after the Turn settles. | 08 and 13 Observability |
| Directive | Typed request for runtime-owned post-commit work. | 06, 08, and the owning Plugin |
| Agent checkpoint | Portable Agent reconstruction data. | 01 and 07 Persistence |
| Persistence record | Durable lifecycle and compare-and-swap envelope. It owns the complete Agent Ref and storage revision. | 07 |
| Plugin declaration | One ordered user declaration of a reusable capability. | 05 Plugins |
| Plugin facet | Proposed owner-specific Agent, Agent Server, Persistence, or Topology behavior. | 05 and the related owner seam |
| Plugin runtime input | Identity, committed owned state, and matching state version for one runtime start. | 05, 08, and 10 Runtime topology |
| Jido instance configuration | Validated local runtime configuration. | 09 Jido instance |
| Public error | Owner-defined failure with a documented normalization rule. | 12 and the operation owner |

The following names identify roles only until their owner seams approve exact
types: Agent Ref, Agent Checkpoint, Agent Commit,
Persistence Record, Agent Status, Turn Status, Plugin Command, Plugin Context,
Plugin Transition, Plugin Contribution, Plugin Runtime Init, Plugin Runtime
Context, Plugin Runtime Status, and Instance Config. This design does not
define `%Jido.Plugin{}` as a configuration value and does not define a new
`Result` struct.

Portable durability roles nest in one direction:

```text
Agent checkpoint, including durable work intent
  -> commit data
  -> persistence record
```

Runtime status values can contain PIDs or other runtime data. They never enter
an Agent, Agent checkpoint, commit-data value, or persistence record. Public
keyword options remain lists. Telemetry measurements and metadata remain maps.

A live Turn execution limit is not required by this seam. If seams 04 and 08
add it, the limit is separate from caller wait timeout and Directive timeout.

## Invariants

These identifiers name cross-system invariant groups. The linked requirements
contain the required behavior.

| Invariant | Stable condition | Requirements |
| --- | --- | --- |
| `OVR-INV-001` | One source Signal selects one fixed executable for one Turn. | `OVR-REQ-013` through `OVR-REQ-015` |
| `OVR-INV-002` | Direct and live paths use one candidate-evaluation boundary. | `OVR-REQ-016` through `OVR-REQ-018` |
| `OVR-INV-003` | Domain state, Plugin state, and candidate assembly have separate write owners. | `OVR-REQ-019` through `OVR-REQ-023` |
| `OVR-INV-004` | One live Turn has one commit point and one state-version increment. | `OVR-REQ-024` through `OVR-REQ-026` |
| `OVR-INV-005` | Executable I/O and runtime-owned Directive work have different commit guarantees. | `OVR-REQ-027` through `OVR-REQ-030` |
| `OVR-INV-006` | Recoverable capability work uses saved intent, stable IDs, and Signal reentry. | `OVR-REQ-031` through `OVR-REQ-034` |
| `OVR-INV-007` | A durable live commit requires confirmed atomic persistence through its owning instance context. | `OVR-REQ-035` through `OVR-REQ-039`, `OVR-REQ-064` |
| `OVR-INV-008` | Durable creation, restore, and deletion have explicit record boundaries. | `OVR-REQ-040` through `OVR-REQ-043` |
| `OVR-INV-009` | Nondurable restart state belongs to one live Jido instance. | `OVR-REQ-044` and `OVR-REQ-045` |
| `OVR-INV-010` | Durable identity, runtime location, and write authority are different concepts. | `OVR-REQ-011`, `OVR-REQ-012`, `OVR-REQ-039`, `OVR-REQ-046` |
| `OVR-INV-011` | Plugin runtime state and handles do not become Agent state. | `OVR-REQ-007`, `OVR-REQ-047` through `OVR-REQ-049` |
| `OVR-INV-012` | Commit and Directive handling are outside Turn cancellation. | `OVR-REQ-050` and `OVR-REQ-051` |
| `OVR-INV-013` | Each public value and error has a clear owner and compatibility rule. | `OVR-REQ-052`, `OVR-REQ-053`, `OVR-REQ-063`, `OVR-REQ-065`, `OVR-REQ-066` |
| `OVR-INV-014` | Observation is bounded and cannot change execution results. | `OVR-REQ-054` through `OVR-REQ-059` |
| `OVR-INV-015` | Jido core stays local and leaves product and distributed-system policy outside. | `OVR-REQ-001` through `OVR-REQ-005`, `OVR-REQ-060` through `OVR-REQ-062` |

## Preferred vocabulary

| Preferred term | Meaning | Do not use as an alias |
| --- | --- | --- |
| Agent definition | Immutable static Agent value with schema, routes, Plugin declarations, metadata, and definition revision. | Agent class, Agent template |
| Agent instance | Immutable Agent value with identity and complete validated state. | live Agent, actor process |
| Agent ID | Supported nonempty string in one Agent instance. | Agent Ref, PID |
| Agent Ref | Stable identity across lookup, storage, delivery, and placement. | PID, server name, persistence key |
| Runtime handle | PID or OTP name for the current activation. | Agent identity |
| Runtime location | Current process or node where an Agent activation runs. | Agent identity, Agent Ref |
| Source Signal | Signal received for the Turn. It never changes. | original event, raw command |
| Effective Signal | Bounded Signal view after allowed admission or preparation. It cannot select a different executable. | rewritten source Signal |
| Turn | One fixed Action or Flow and its input for one source Signal. | transaction, job |
| Executable | Selected Action or Flow. | handler, route result |
| Candidate Agent | Complete validated immutable Agent proposed by evaluation. | next live state, commit |
| Evaluation return | Direct `Jido.Agent.cmd/3` result. It proves no live or durable commit. | live result, Turn Outcome |
| Live result | Tagged live reply at the commit boundary. | Result struct, Turn Outcome |
| State version | Integer that advances once for each successful live Turn commit. | storage lease, definition revision |
| Commit | Operation that makes one candidate Agent live after required persistence succeeds. | candidate, persistence write |
| Turn Outcome | Terminal observation after Directive work settles or the Turn stops. | live result, commit result |
| Directive | Typed request for runtime-owned post-commit work. | guaranteed durable effect |
| Durable work intent | Portable pending work with a stable operation ID in Agent or Plugin state. | Directive queue, universal outbox |
| Runtime checkpoint | Nondurable in-instance snapshot for abnormal nonpersistent Server restart. | persistence record, initial Agent |
| Agent checkpoint | Portable Agent reconstruction data. | runtime checkpoint, Codec document |
| Persistence record | Durable lifecycle and compare-and-swap envelope. | Agent identity, checkpoint |
| Write authority | Permission for the current activation to do another durable commit. | PID ownership, Registry presence |
| Definition revision | Module-owned revision of normalized Agent-definition meaning. It does not pin loaded BEAM code by itself. | state version, package version |
| Plugin | User-declared reusable capability. | adapter, authoring extension |
| Plugin facet | Proposed owner-specific Plugin behavior. | arbitrary hook, adapter |
| Plugin runtime | Supervised resources for one Plugin on one Agent activation. | Plugin state |
| Jido instance | Named local supervision and service boundary. | namespace, cluster |
| Runtime topology | OTP process and ownership layout below one Jido instance. | Topology definition |
| Topology control plane | Static definitions, plans, repair, and possible future live target control. | Agent pool |
| Adapter | Replaceable external service boundary. | Plugin facet |
| Provider | Instance infrastructure behind one fixed core boundary. | Plugin, Agent policy |
| Authoring extension | Static syntax that lowers to canonical values. | runtime Plugin |

## Downstream guarantees

These guarantees apply only after the related Overview requirements are
approved. Detailed owner contracts remain open.

| Consumer seam | Guaranteed shared contract after approval |
| --- | --- |
| 90 Package boundaries | Jido is the local coordination layer above `jido_action` and `jido_signal`. Extension categories stay separate. |
| 12 Errors and contracts | Each public value and error has one owner. Live result and Turn Outcome are different. Documented protocol exceptions can use maps, tuples, or OTP values. |
| 01 Agent | Agent definitions and instances are immutable. Domain and Plugin state have separate write owners. Agent values have no runtime handles. |
| 02 Agent authoring | DSL, direct data, Builder, Codec, and inline Actions reach one normalized definition contract. |
| 03 Agent identity | Stable identity, location, and write authority are separate. Ref-first migration keeps supported ID and PID APIs. |
| 04 Turn evaluation | One source Signal selects one fixed executable. Direct and live paths share candidate evaluation. |
| 05 Plugins | One ordered Plugin declaration can contain owner-specific behavior. Owned state and isolated input remain separate. |
| 06 Commit and effects | One live commit follows validation and required persistence. Directive work is post-commit. Executable I/O can occur before commit. |
| 07 Persistence | Binary adapters and atomic compare-and-swap remain. Durable lifecycle adds initial active records, write-authority loss, and tombstones. |
| 08 Agent Server | The Server is the serialized live owner. Each successful commit advances one state version. Runtime-checkpoint restore remains. |
| 09 Jido instance | The instance owns local services, lookup, supervision, runtime checkpoints, and live persistence context. |
| 10 Runtime topology | Agent Servers are peers. Plugin runtimes are capability resources. Replacement uses matching state and version. |
| 11 Topology control plane | Static local Topology and repair remain supported. Authoring ownership does not prove live runtime control. |
| 13 Observability | Semantic Turn, commit, Directive, lifecycle, and settlement boundaries are the target. Observation is bounded and has no execution authority. |
| 99 Delivery | A supported API remains until an approved migration and acceptance evidence permit a change. |

## Open design decisions

All options in this table are recommendations and are pending approval.

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `OVR-DEC-001` | Which route selects the executable? | Select the first Router match from the source Signal before Plugin preparation. | Ambiguous routes become deterministic. Route-changing Plugins need migration. |
| `OVR-DEC-002` | What does abnormal nonpersistent restart restore? | Restore the latest in-instance runtime checkpoint and state version. | Abnormal same-instance restart preserves the latest committed state. |
| `OVR-DEC-003` | Is stable Agent Ref in V3 scope? | Yes. Add it beside supported ID and PID APIs. | Seams 03, 07, 09, and 10 need a staged identity migration. |
| `OVR-DEC-004` | How does definition revision work? | Use a positive module-owned revision, preserve it through all authoring forms, and define an old-checkpoint rule. | Restore can reject a definition mismatch. Executable code pinning stays open. |
| `OVR-DEC-005` | How is Plugin behavior divided? | Use Agent, Agent Server, Persistence, and Topology as proposed facet owners under one ordered Plugin declaration. | Seam 05 can separate mixed ownership without changing declaration order. |
| `OVR-DEC-006` | Do complete custom checkpoint callbacks remain? | Keep `checkpoint/2` and `restore/2` until Persistence-facet composition is explicit. | No Plugin facet can silently replace custom checkpoint meaning. |
| `OVR-DEC-007` | Which durability changes are in V3 scope? | Require initial active records, loss of write authority after every write error, and tombstones. | Seams 07 and 08 need behavior changes and migration evidence. |
| `OVR-DEC-008` | Which supported APIs remain for V3? | Keep Builder, Codec, neutral definitions, owned children, public PID APIs, persistence adapters, and local debug paths. | New APIs are additive until a separate deprecation decision. |
| `OVR-DEC-009` | How much live Topology control is in V3? | Keep static local activation and repair. Defer owner-Agent live control and target updates. | Live upgrade does not block V3. |
| `OVR-DEC-010` | Which services belong in Jido core? | Keep core local. Keep general durable, cluster, and transport services in focused packages. | No unproved external package API becomes a V3 dependency. |
| `OVR-DEC-011` | Does this seam approve exact new public structs? | No. Approve roles only and let seam 12, seam 90, and value owners decide types. | Supported maps, tuples, and structs remain until a staged replacement is approved. |
| `OVR-DEC-012` | Which observation APIs remain during migration? | Make semantic Agent events the target and keep legacy telemetry, `Jido.Observe`, and debug paths. | Seam 13 must prove replacement coverage before removal. |
