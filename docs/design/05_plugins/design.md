> Target seam design. This document is pending approval.

# Plugin design

All requirements and decisions in this document are recommended targets. EARS
syntax does not mean that the user approved a requirement.

## Scope and owner

- Owner: the Plugin declaration, normalization, and owner-specific extension
  contracts.
- In scope: package manifests, facet selection, Plugin-owned state metadata,
  bounded callback data, Directive ownership, optional runtime declarations,
  pure state conversion, pure Topology contribution, scheduled occurrences,
  and compatibility normalization.
- Out of scope: Agent domain state, Signal Router precedence, Action and Flow
  execution, Agent Server process policy, commit and settlement, persistence
  records and storage I/O, live Topology control, transport, and general durable
  workflow orchestration.
- Adjacent owners: seam 01 owns the combined Agent state value. Seam 04 owns
  fixed Turn selection and candidate assembly. Seam 08 owns live execution and
  Plugin runtime lifecycle. Seam 07 owns persistence records and adapters. Seam
  11 owns Topology planning and activation. Seam 12 owns public error shapes.

## Model

A Plugin is one reusable capability that a developer declares in an Agent
definition. The declaration stays small and ordered:

```elixir
plugins: [
  {MyApp.Scheduler, timezone: "Etc/UTC"},
  MyApp.Audit
]
```

The target normalizer treats each declared module as a callback-free package
manifest. It validates common options and selects no more than one facet for
each owner:

```text
Plugin declaration
  -> neutral manifest and common options
  -> Agent facet Spec
  -> Agent Server facet Spec
  -> optional Persistence facet Spec
  -> optional Topology facet Spec
```

The four facets are a closed initial set:

| Facet owner | Authority | Exclusions |
| --- | --- | --- |
| Agent | Pure preparation, declared state view, one optional state key, Directive declaration and contribution | PID, runtime handle, persistence I/O, commit, Topology activation |
| Agent Server | Live admission, outbound Signal preparation, one optional runtime root, readiness, post-commit Directive handling | Agent state write, route selection, persistence result change |
| Persistence | Pure dump and load of one paired Plugin-owned state value | Complete Agent, adapter, key, revision, write result, process |
| Topology | Pure lowering to bounded canonical Topology entries | Process start, persistence, live reconciliation, arbitrary resource types |

The manifest and owner Specs contain static configuration only. Jido owners
call their facets. A facet does not call a sibling facet.

Plugin state remains one top-level field in the complete Agent state map. The
Agent facet owns that field's schema and contributions. The Agent Server owns
all live runtime handles. The persistence owner stores the complete checkpoint.
A Persistence facet can only convert its paired Plugin-owned value.

The Turn sequence is:

```text
source Signal
  -> live admission, when used
  -> fixed source-Signal Turn selection
  -> ordered isolated Agent facet preparation
  -> one Action or Flow execution
  -> ordered bounded Plugin contributions
  -> complete candidate validation
```

Live commit, Directive handling, and outbound delivery follow this sequence but
are not Plugin-owned operations.

## Requirements

### Declaration, manifest, and normalization

`PLG-REQ-001`: When an Agent declares Plugins, the Plugin declaration boundary
shall accept an ordered list of modules or `{module, keyword_options}` pairs.

`PLG-REQ-002`: When the Plugin boundary normalizes a declaration, it shall
produce one neutral manifest result for the declared package module.

`PLG-REQ-003`: If an Agent declares the same Plugin package module more than
once, then the Plugin boundary shall reject the definition.

`PLG-REQ-004`: When the Plugin boundary normalizes package options, it shall
validate common options one time before it builds an owner Spec.

`PLG-REQ-005`: When a manifest selects facets, the Plugin boundary shall accept
no more than one Agent, Agent Server, Persistence, and Topology facet module.

`PLG-REQ-006`: When a Jido owner builds a Plugin Spec, the Plugin boundary shall
exclude live data and fields owned by another facet from that Spec.

`PLG-REQ-007`: When module DSL, direct data, Builder, or Codec produces Plugin
declarations, the Agent authoring boundary shall preserve declaration order.

`PLG-REQ-008`: Where an Agent declares no Plugins, the Plugin boundary shall add
no Plugin dependency to direct Turn evaluation.

`PLG-REQ-009`: When Agent Codec encodes a Plugin declaration, the Agent authoring
boundary shall encode only the package module and validated static options.

`PLG-REQ-010`: When Agent Codec encodes a Plugin declaration, the Agent authoring
boundary shall exclude Plugin state, facet runtime data, and process handles.

### Schema and state ownership

`PLG-REQ-011`: Where a Plugin has an Agent facet with state, the Agent facet
shall declare one atom key and one static Zoi schema for its complete owned
state value.

`PLG-REQ-012`: If a Plugin state key duplicates a domain-state key or another
Plugin state key, then the Agent construction boundary shall reject the Agent
definition.

`PLG-REQ-013`: When the Agent boundary constructs the complete state schema, it
shall add each Plugin-owned field at the top level of the combined Agent state
map.

`PLG-REQ-014`: If an Action or Flow changes a Plugin-owned state field, then the
Turn evaluator shall reject the executable result.

`PLG-REQ-015`: When an Agent facet contributes state, the Turn evaluator shall
allow it to replace only its complete owned state field.

`PLG-REQ-016`: When an Agent facet returns a changed state value, the Plugin
boundary shall validate the value with that facet's current state schema.

`PLG-REQ-017`: When the Plugin boundary accepts Plugin state or prepared Plugin
input, it shall apply the approved seam-12 recursive portable-value rule.

### Admission, route boundary, and preparation

`PLG-REQ-018`: When a live Agent Server admits a Signal, the Agent Server facet
boundary shall preserve the unchanged source Signal for Turn selection.

`PLG-REQ-019`: When more than one Agent Server facet participates in admission,
the Agent Server shall call them serially in declaration order.

`PLG-REQ-020`: If an Agent Server facet rejects admission, then the Agent Server
shall stop admission at that facet and start no executable work.

`PLG-REQ-021`: When an Agent Server facet admits input, the Agent Server shall
allow it to add only bounded caller context and no executable selection.

`PLG-REQ-022`: When Plugin preparation starts, the Turn evaluator shall already
have one executable selected from the source Signal.

`PLG-REQ-023`: When an Agent facet prepares a Turn, the Plugin boundary shall
give it only its declared Agent projection, its owned state, its options, the
source Signal, the effective Signal, and its own prepared input.

`PLG-REQ-024`: When an Agent facet returns prepared input, the Turn evaluator
shall store that input under only that Plugin package identity.

`PLG-REQ-025`: When a later Plugin prepares the same Turn, the Plugin boundary
shall not expose or let it replace another Plugin's prepared input.

`PLG-REQ-026`: When an Agent facet returns an effective Signal, the Plugin
boundary shall validate the complete Signal before the next facet runs.

`PLG-REQ-027`: When Plugin preparation changes the effective Signal, the Turn
evaluator shall not change the source Signal, selected executable, or route
defaults.

`PLG-REQ-028`: When more than one Agent facet prepares a Turn, the Plugin
boundary shall call them serially in declaration order and stop at the first
failure.

`PLG-REQ-029`: When executable work starts, the Turn evaluator shall give the
selected executable a read-only map of prepared Plugin inputs keyed by Plugin
package identity.

### Contribution and Directives

`PLG-REQ-030`: When an Agent facet contributes after executable success, the
Plugin boundary shall give it only its declared before-and-after Agent
projection, owned prepared input, current owned state, options, and owned Turn
Directives.

`PLG-REQ-031`: When more than one Agent facet contributes, the Plugin boundary
shall call them serially in declaration order and stop at the first failure.

`PLG-REQ-032`: When an Agent facet returns no state change, the Turn evaluator
shall preserve that Plugin's current complete state value.

`PLG-REQ-033`: When an Agent facet adds Directives, the Plugin boundary shall
accept only Directive types owned by that facet.

`PLG-REQ-034`: When Agent facets add Directives, the Turn evaluator shall append
them after executable Directives in Plugin declaration order.

`PLG-REQ-035`: If preparation or contribution fails, then the Turn evaluator
shall return no candidate Agent.

`PLG-REQ-036`: When a Plugin declares a Directive type, the Plugin boundary
shall assign that type to only one Agent facet.

`PLG-REQ-037`: When the Turn evaluator accepts a Plugin Directive, it shall
validate the complete Directive before candidate return.

`PLG-REQ-038`: Where a Plugin Directive changes only Plugin-owned state and has
no live handler, the Agent Server shall treat its successful pre-commit
contribution as complete handling.

`PLG-REQ-039`: Where an Agent Server facet handles a Plugin Directive, the
Plugin boundary shall require the paired Agent facet to own that Directive
type.

`PLG-REQ-040`: When a live commit succeeds, the Agent Server shall start Plugin
Directive handling after the committed Agent and state version are authoritative.

`PLG-REQ-041`: Where a Plugin Directive has a process-free handler, the Agent
Server shall run it in the same bounded post-commit task contract as a
runtime-backed handler.

`PLG-REQ-042`: If post-commit Plugin Directive handling fails, then the Agent
Server shall preserve the committed Agent and state version.

### Agent Server facet and runtime lifecycle

`PLG-REQ-043`: Where an Agent Server facet declares a runtime, the Agent Server
shall accept only one valid OTP child specification with `restart: :permanent`.

`PLG-REQ-044`: Where a Plugin declares no runtime, the Agent Server shall not
start a Plugin process for that package.

`PLG-REQ-045`: If a declared Plugin runtime is unavailable, then the Agent
Server shall return a runtime error and shall not use a process-free handler as
a fallback.

`PLG-REQ-046`: When an Agent Server starts a Plugin runtime, it shall wait for
the facet readiness result before it reports the Agent Server as ready.

`PLG-REQ-047`: When a new Agent activation starts a Plugin runtime at state
version zero, the Agent Server shall give the runtime its validated initial
owned state and state version zero in one immutable input.

`PLG-REQ-048`: When a Plugin runtime is replaced, the Agent Server shall give it
the latest committed owned state and the matching Agent state version in one
immutable input.

`PLG-REQ-049`: While a Plugin runtime is starting or running, the Agent Server
shall keep its PID, timers, monitors, tasks, and readiness data outside Agent
state and checkpoints.

`PLG-REQ-050`: When a Plugin runtime requests an Agent state change, it shall
send a Signal through the public Agent mailbox boundary.

`PLG-REQ-051`: When outbound Signal preparation runs, the Agent Server shall
call participating facets in reverse declaration order with only their owned
committed state and bounded delivery context.

`PLG-REQ-052`: If an outbound Signal facet returns an invalid Signal or a
failure, then the Agent Server shall stop outbound preparation before delivery.

### Persistence and Topology facets

`PLG-REQ-053`: Where a Plugin declares a Persistence facet, the Plugin boundary
shall require a paired stateful Agent facet.

`PLG-REQ-054`: When a Persistence facet dumps or loads Plugin state, the
Persistence boundary shall give it only its paired Plugin-owned state value,
stable format context, and static options.

`PLG-REQ-055`: When a Persistence facet dumps Plugin state, the Persistence
boundary shall reject nonportable output before adapter work starts.

`PLG-REQ-056`: When a Persistence facet loads Plugin state, the Persistence
boundary shall validate the loaded value with the current Agent facet state
schema before a Plugin runtime starts.

`PLG-REQ-057`: The Persistence boundary shall prevent a Plugin Persistence
facet from inspecting or changing the adapter, key, expected revision, write
result, complete Agent state, or commit decision.

`PLG-REQ-058`: Where a complete custom Agent checkpoint callback remains in
use, the Persistence boundary shall bypass Plugin Persistence facets until an
approved checkpoint-composition migration replaces that compatibility rule.

`PLG-REQ-059`: When a Topology facet contributes static data, the Topology
boundary shall accept only bounded entries that lower to supported canonical
Topology values.

`PLG-REQ-060`: When a Topology facet contributes static data, the Topology
boundary shall run no process start, persistence operation, or live
reconciliation.

### Scheduled occurrences and recoverable capability work

`PLG-REQ-061`: Where Scheduler recurring work includes a generation, the
Scheduler shall derive one opaque occurrence ID from its versioned identity
scope, job ID, generation, and scheduled UTC instant.

`PLG-REQ-062`: When Scheduler derives an occurrence ID, it shall exclude node,
PID, arrival time, and Signal ID from the occurrence coordinates.

`PLG-REQ-063`: When Scheduler delivers the same occurrence again, it shall keep
the occurrence ID and create a fresh Signal ID.

`PLG-REQ-064`: When Scheduler adds tracked occurrence metadata, it shall keep
Signal data and unrelated context unchanged.

`PLG-REQ-065`: If tracked occurrence metadata is absent, malformed, or
incomplete, then the Scheduler occurrence accessor shall return its documented
tagged error.

`PLG-REQ-066`: When Scheduler accepts a tracked recurring schedule, it shall
require a generation from 0 through 2,147,483,647.

`PLG-REQ-067`: Where a recurring schedule omits generation, the Scheduler shall
preserve the untracked definition and delivery behavior.

`PLG-REQ-068`: When Scheduler creates a one-shot delayed Signal, it shall keep
that timer and pending work outside Agent state and checkpoint recovery.

`PLG-REQ-069`: Where Scheduler durable delivery is enabled, the Scheduler shall
require an explicit generation and a configured enqueue route.

`PLG-REQ-070`: When a durable occurrence becomes due, the Scheduler shall
commit one portable pending business Signal before it attempts business work.

`PLG-REQ-071`: While one job has pending durable work, the Scheduler shall keep
at most that one pending occurrence and skip later slots for that job.

`PLG-REQ-072`: Where committed Scheduler work is pending, when its runtime
starts or restarts, the Scheduler shall retry that pending occurrence.

`PLG-REQ-073`: When business work acknowledges a pending occurrence, the
Scheduler shall remove the pending value in the same Agent commit as the
business state change.

`PLG-REQ-074`: If a durable tick is completed, cancelled, replaced, or has a
different payload, then Scheduler preparation shall reject that tick before
business executable work starts.

`PLG-REQ-075`: When `delivery_interval` is configured, the Scheduler shall
accept only an integer from 1 through 4,294,967,295 milliseconds and shall use
it between completed pending-work attempts.

`PLG-REQ-076`: Where durable Scheduler delivery can repeat external work before
acknowledgement, the Scheduler public contract shall identify the occurrence ID
as the duplicate-handling key.

## Public contract

### Manifest and facets

`Jido.Plugin` remains the package declaration entry. In the target model its
generated metadata contains static facet module identities, common option
validation, facet option mapping, and explicit package or facet revisions. It
contains no Turn, process, persistence, or Topology callback.

The recommended facet behaviors are `Jido.Agent.Plugin`,
`Jido.AgentServer.Plugin`, `Jido.Persistence.Plugin`, and
`Jido.Topology.Plugin`. Exact callback value module names remain an open naming
decision. Each value must be a validated public struct because it crosses a
package callback boundary. The required roles are:

| Value role | Required content | Excluded content |
| --- | --- | --- |
| Preparation input | Source Signal, effective Signal, package identity, owned prepared input | Complete Agent, other Plugin input, route handle |
| Agent facet context | Package module, static options, Agent ID, Agent module, owned state, declared Agent projection | PID, complete state, runtime and persistence data |
| Transition view | Source and effective Signal identity, declared before and after fields, owned Directives | Complete executable output, other contributions |
| Contribution | Complete owned state or unchanged marker, added owned Directives | Domain state and foreign Directives |
| Runtime init | Live Agent identity, package module, options, committed owned state, matching state version | Complete Agent, persistence adapter, prior runtime handle |
| Directive context | Turn identity, source and effective Signal, committed owned state and version, bounded transient context | Complete private Agent Server state |
| Outbound context | Turn identity, source and effective Signal, target, committed owned state and version | Complete private Agent Server state |

Direct evaluation has an Agent ID and module but no required Jido instance or
Agent Ref. A live runtime uses the approved identity value when seam 03 and the
instance seam make it available. Runtime identity, module identity, and state
version remain separate.

### Callback authority

The Agent facet has pure preparation and contribution callbacks. Preparation
can reject input, return a valid effective Signal, and set one owned prepared
value. Contribution can replace one complete owned state value and add owned
Directives. It cannot select a route, do commit work, or use a runtime handle.

The Agent Server facet can admit live input, prepare outbound Signals, declare
one optional child, report readiness, and handle paired Directives after commit.
The Agent Server owns callback tasks, limits, start order, restart, errors, and
settlement.

The Persistence facet has pure dump and load callbacks for one owned value.
The Persistence owner decides checkpoint and record order. The adapter remains
a separate byte-storage contract. The Topology facet has one pure contribution
callback. The Topology owner validates the complete definition and plan.

### Scheduled occurrence contract

Scheduler version-1 occurrence identity keeps the implemented coordinate scope:
Jido instance, Agent ID, partition, job ID, generation, and scheduled UTC
instant. The digest is SHA-256 over deterministic Erlang external-term encoding
with minor version 2. The Signal context fields are `jidooccurrenceid`,
`jidoschedulegen`, and `jidoscheduledat`; `jidodurabletick` marks a durable
delivery. These names and existing IDs remain compatible through the facet
migration. A later Agent Ref identity version needs a separate versioned ID
decision.

Durable Scheduler delivery is capability-owned recoverable work. It is not a
general Directive guarantee, catch-up queue, distributed lease, external-effect
transaction, or exactly-once contract. `time_scale` changes recurring clock
input only. Clock process state is not checkpoint data. `delivery_timeout`
limits one state read and delivery call. `retry_delay_ms` controls retry after a
runtime schedule fails to start. These options do not change occurrence
identity.

## Invariants

- `PLG-INV-001`: One ordered Plugin declaration produces static owner-specific
  Specs and no runtime data.
- `PLG-INV-002`: Domain state and each Plugin state field have separate write
  owners inside one combined Agent state map.
- `PLG-INV-003`: One source Signal selects one executable before Plugin
  preparation.
- `PLG-INV-004`: A Plugin sees and changes only its declared Turn data.
- `PLG-INV-005`: Plugin runtime handles never enter Agent state or checkpoints.
- `PLG-INV-006`: Live Plugin Directive work starts only after commit and cannot
  undo that commit.
- `PLG-INV-007`: A Persistence facet cannot change storage or commit meaning.
- `PLG-INV-008`: A Topology facet is static and has no live authority.
- `PLG-INV-009`: Recoverable Scheduler work uses saved intent, stable occurrence
  identity, acknowledgement, and Signal reentry.
- `PLG-INV-010`: A supported mixed Plugin behavior remains available until its
  staged migration has parity proof.

## Downstream guarantees

These guarantees apply only after the related requirements are approved.

| Consumer seam | Guaranteed contract |
| --- | --- |
| 01 Agent | Plugin schemas stay in the combined state map with unique ownership and portable-value checks. |
| 02 Agent authoring | One ordered package declaration and static options are enough for all facets and Codec. |
| 04 Turn evaluation | Route selection is fixed before bounded preparation; contribution order and authority are explicit. |
| 06 Commit and effects | Plugin contribution ends before candidate return; live Plugin work is post-commit. |
| 07 Persistence | Optional conversion sees one owned value and cannot change adapter or record semantics. |
| 08 Agent Server | Admission, runtime start, readiness, outbound preparation, and Directive handling use bounded facet contracts. |
| 10 Runtime topology | A replacement runtime receives one committed state and matching version; handles remain runtime-only. |
| 11 Topology control plane | Plugin contributions are pure canonical plan data and do not grant live control. |
| 12 Errors and contracts | Callback faults, invalid results, and nonportable values use owner-defined errors. |
| 99 Delivery | Mixed behavior removal waits for built-in and public-only compatibility proof. |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `PLG-DEC-001` | What is the Plugin architecture? | Use one callback-free manifest and four owner-specific facets. | Mixed ownership has a staged replacement. |
| `PLG-DEC-002` | Where is Plugin state stored? | Keep one Plugin-owned top-level key in the combined Agent state map. | Agent and checkpoint shapes remain compatible. |
| `PLG-DEC-003` | What can pure callbacks observe? | Use declared top-level Agent fields, owned state, owned input, and owned Directives only. | Cross-Plugin reads and writes are denied. |
| `PLG-DEC-004` | Can contribution add Directives? | Yes. Accept only owned types and append them in declaration order. | Plugins can request bounded post-commit work without domain-state authority. |
| `PLG-DEC-005` | Which live callbacks remain? | Keep admission and reverse-order outbound preparation in the Agent Server facet. | Current live behavior can migrate without removal. |
| `PLG-DEC-006` | Does state-only reduction handle a live Directive? | Yes, when no live handler is declared. | Existing state-only Plugins do not gain a required runtime callback. |
| `PLG-DEC-007` | How does runtime bootstrap work? | Put committed owned state and matching state version in one immutable Init value. | First start and replacement use a coherent view. |
| `PLG-DEC-008` | How do complete custom checkpoints interact with a Persistence facet? | Bypass the facet during the first compatibility stage. | Existing callback meaning stays intact while a later API can separate domain conversion. |
| `PLG-DEC-009` | Which callback and value names are public? | Use owner namespaces and choose exact names during API review before implementation. | The semantic contract can be approved without locking weak names. |
| `PLG-DEC-010` | Does Scheduler occurrence identity change to Agent Ref now? | No. Keep version 1 and require a separate versioned migration. | Existing occurrence IDs remain stable. |
| `PLG-DEC-011` | Can Plugins be installed dynamically into a live Agent? | No for the first facet contract. | Static definition, state schema, and ownership stay coherent. |
| `PLG-DEC-012` | Can one package declare several facets for one owner? | No for the first facet contract. Compose them behind one module. | Order and ownership remain unambiguous. |
