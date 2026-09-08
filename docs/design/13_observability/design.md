# Jido V3 observability design

Status: Pending approval.

All requirements in this file are target requirements. A requirement is not a
claim that the current code implements it. Current proof and gaps are in
[alignment.md](alignment.md).

## Scope and owner

Jido owns semantic observation for the Agent runtime that it owns. This
includes Agent lifecycle, live Turn evaluation, commit, Directive handling,
Agent persistence, admission rejection, and the static local Topology
Controller. The package that owns an optional distributed control plane owns
its control-plane event names and emission points.

`jido_action` owns execution and Flow telemetry. `jido_signal` owns the Signal
envelope and its portable W3C trace carrier. `jido_ai` owns model, tool, token,
quota, and AI-policy observation. A host application owns reporters,
OpenTelemetry SDK start, sampling policy, exporters, collectors, credentials,
storage, dashboards, and alerts.

Telemetry, logs, traces, metrics, and debug history are observation channels.
They do not authorize work, make a result durable, or replace audit records.

## Model

### Semantic facts

The contract separates these facts:

1. An Agent activation or stop crossed a lifecycle boundary.
2. An admitted Turn started and reached a live result or a pre-commit failure.
3. A commit attempt completed.
4. Post-commit Directive work completed or failed.
5. The Turn reached its terminal Outcome.
6. A request did not enter a Turn because admission rejected it.
7. A persistence or local Topology operation completed.

The live Turn result and terminal settlement are not the same fact. A caller
can receive a committed Agent before Directive work settles. A later Directive
failure does not undo that commit.

### Event catalog

The first five rows exist now. The last three rows are target additions.

| Family | Event name | Shape | Meaning |
| --- | --- | --- | --- |
| Agent lifecycle | `[:jido, :agent, :lifecycle, event]` | Span | One real Agent lifecycle operation |
| Agent Turn result | `[:jido, :agent, :turn, event]` | Span | From Turn admission to live result or pre-commit failure |
| Agent commit | `[:jido, :agent, :commit, event]` | Span | One live commit attempt, including required persistence |
| Agent Directive | `[:jido, :agent, :directive, event]` | Span | One post-commit Directive attempt |
| Turn settlement | `[:jido, :agent, :turn, :settled]` | Point | One terminal public Turn Outcome |
| Admission rejection | `[:jido, :agent, :admission, :rejected]` | Point | A call or cast did not enter a Turn |
| Agent persistence | `[:jido, :persistence, :operation, event]` | Span | One public Agent persistence operation |
| Local Topology | `[:jido, :topology, :operation, event]` | Span | One static local Controller operation |

For a span, `event` is `:start`, `:stop`, or `:exception`. A returned failure
uses `:stop`. A raised, thrown, or exited fault that escapes the observed
boundary uses `:exception`. A point event has no matching start event.

Lifecycle operations are `:activate`, `:stop`, `:hibernate`, and `:thaw`.
Record creation and deletion are persistence operations. Persistence operations
are `:load`, `:compare_and_swap`, and `:delete`. Local Topology operations are
`:activate`, `:repair`, and `:cleanup`. These are target vocabularies. The
current lifecycle emitter only reports `:activate` and `:stop`.

### Status and stage vocabularies

| Field | Values | Rule |
| --- | --- | --- |
| `status` | `:ok`, `:error`, `:cancelled`, `:timed_out`, `:conflict`, `:indeterminate`, `:not_found`, `:rejected` | Use the narrow public result. Do not put a raw reason in this field. |
| `stage` | `:evaluate`, `:commit`, `:directive` | Collapse private prepare, execute, finalize, and Plugin callback stages into `:evaluate`. |
| `kind` | `:error`, `:throw`, `:exit` | Include only on `:exception`. |
| `admission_reason` | `:deadline_expired`, `:overloaded` | Report why work did not enter a Turn. |
| `persistence_reason` | `:commit`, `:activate`, `:stop`, `:hibernate`, `:thaw`, `:manual`, `:topology` | Report why the owner requested storage work. |

A caller-side wait timeout is not an admission event. The Server must reject
the work before the admission boundary emits `admission.rejected`.

### Metadata contract

Semantic metadata is an allowlist. A field can be absent when it does not
apply or when its source value does not pass validation.

| Group | Fields | Value rule |
| --- | --- | --- |
| Schema | `schema_version` | Positive integer; target version starts at `1` |
| Agent Ref | `agent_namespace`, `agent_partition`, `agent_id` | Bounded UTF-8 strings projected from `%Jido.Agent.Ref{}` after that value exists |
| Current identity overlap | `jido_instance`, `partition` | Current atom/string/integer fields retained only for compatibility |
| Agent runtime | `agent_module`, `activation_id` | Module atom and bounded ID |
| Turn and Signal | `turn_id`, `source_signal_id`, `signal_id`, `signal_type` | Bounded UTF-8 strings |
| Causal trace | `trace_id`, `span_id`, `parent_span_id`, `causation_id`, `cause_turn_id`, `child_activation_id`, `sampled?` | Bounded IDs and Boolean sampling hint |
| Result | `operation`, `status`, `stage`, `kind`, `committed?` | Registered atoms and Boolean |
| Safe error | `error_class`, `error_type`, `error_code`, `retryable?` | Bounded public projection from seam 12; current code only supplies type and retryability |
| Directive | `directive_module` | Module atom |
| Admission | `admission_reason` | Registered atom |
| Persistence | `adapter_module`, `persistence_reason` | Module atom and registered atom |
| Topology | `topology_id`, `topology_operation`, `component_kind`, `node_id` | Bounded strings or registered atoms |

The target maximum is 256 bytes for an ID or type and 128 bytes for a
partition. Invalid UTF-8, larger strings, nested values, and values outside the
allowlist are omitted. New code must not convert untrusted strings to atoms.

`agent_namespace`, `agent_partition`, and `agent_id` are the observation
projection of the Agent Ref in seam 03. They identify a logical Agent. An
`activation_id` identifies one runtime activation. A `turn_id` identifies one
admitted Turn. Trace parentage and Signal causation stay separate because they
answer different questions.

Semantic metadata excludes Agent state, Plugin state, Signal data, Directive
data, caller context, checkpoints, persistence records, encoded keys, raw
errors, error details, error messages, stacktraces, PIDs, ports, references,
functions, authenticated actor data, arbitrary application metadata, and
OpenTelemetry `tracestate`. An audit record, not telemetry, owns authenticated
actor and operator request data.

An optional control-plane package owns its event prefix. Its transition event
metadata can contain only `schema_version`, registered `operation`, the
applicable Agent Ref projection, bounded `node_id`, registered `phase`, and
registered result `status`. It reports `epoch` as a numeric measurement. It
does not put desired-placement maps, membership snapshots, leases, credentials,
or operator input in telemetry.

### Measurement contract

All times and durations use the Erlang native time unit unless a consumer
converts them at its boundary. Counts and revisions are integers.

| Event | Required measurements | Optional measurements |
| --- | --- | --- |
| Every `:start` | `system_time`, `monotonic_time` | Event-specific starting values |
| Every `:stop` or `:exception` | `duration` | Event-specific result values |
| Turn start | `state_version_before` | None |
| Turn result | `state_version_before` | `state_version_after`, `directive_count` |
| Turn settled | `duration`, `state_version_before`, `directive_count`, `directive_completed`, `directive_failed`, `directive_skipped` | `state_version_after` |
| Commit | `duration` | `expected_revision`, `state_version_before`, `state_version_after`, `directive_count` |
| Directive | `duration`, `directive_index` | None |
| Admission rejection | `system_time`, `queue_depth` | `queue_limit`, `wait_duration` |
| Persistence | `duration` | `expected_revision`, `revision_before`, `revision_after` |
| Local Topology | `duration` | `component_count`, `ready_count`, `failed_count`, `epoch` |

The `turn.settled` duration measures from Turn start to settlement. It is not
the live-result duration from the Turn span.

### Default consumer contract

The target default metric set has count and duration metrics for lifecycle,
Turn result, settlement, commit, Directive, persistence, and local Topology.
It also has an admission rejection counter. Default metric tags can use only
the fixed vocabularies `operation`, `status`, `stage`, `admission_reason`,
`persistence_reason`, `topology_operation`, and `component_kind`. A reporter
can select a smaller set.

Default metrics must not tag module names, Signal types, Agent Ref fields,
activation IDs, Turn IDs, Signal IDs, trace IDs, topology IDs, node IDs, error
messages, or error codes. Hosts can build explicit high-cardinality views
outside Jido.

The target semantic logger has modes `:off`, `:errors`, `:interesting`, and
`:all`. `:errors` logs non-OK terminal facts. `:interesting` also logs configured
slow operations, admission rejection, non-OK persistence, degraded Topology
operations, and committed Turns with failed Directives. `:all` logs every
semantic terminal event. It does not log span starts by default.

### OpenTelemetry boundary

If approved, `Jido.OpenTelemetry` is an optional translation layer over the
semantic Telemetry contract. It maps only the events in this catalog. It does
not use old Agent Server events, `Jido.Observe` callbacks, or debug history as
its source.

The bridge can depend on an optional OpenTelemetry API. It must not start an
SDK or exporter. It must not perform network I/O in a Telemetry handler. A host
can attach the bridge, configure sampling, and select an exporter.

The bridge must preserve the difference between the live Turn result and Turn
settlement. The exact Turn span end is an open decision. One valid mapping ends
the span at the live result and emits settlement as a correlated point. Another
valid mapping keeps one logical Turn span open until settlement and records the
live result as an earlier event. Neither mapping can label result duration as
settlement duration.

Jido-owned Task boundaries must transfer trace context explicitly. Lower-level
packages transfer context for tasks that they own. A Signal remains the
portable carrier across processes, nodes, queues, and durable boundaries.

## Requirements

### Purpose and ownership

`OBS-REQ-001`: The Jido observation boundary shall use the semantic event
catalog in this file as its stable runtime observation source.

`OBS-REQ-002`: When an observation handler receives a semantic event, the
handler shall have no authority to change Agent state or a runtime decision.

`OBS-REQ-003`: When `Jido.Agent.cmd/3` evaluates an Agent value without an Agent
Server, the Agent observation boundary shall emit no Agent runtime event.

`OBS-REQ-004`: Where a lower package executes an Action or Flow, Jido shall not
rename that package's execution telemetry as an Agent runtime event.

`OBS-REQ-005`: When Jido emits a semantic event, Jido shall use an event name
from the event catalog.

### Lifecycle, Turn, commit, and Directive visibility

`OBS-REQ-006`: When an Agent Server starts one activation, the Agent lifecycle
boundary shall emit one `:activate` span from initialization through Plugin
readiness.

`OBS-REQ-007`: When Jido performs an approved Agent lifecycle operation, the
Agent lifecycle boundary shall identify it as `:activate`, `:stop`,
`:hibernate`, or `:thaw`.

`OBS-REQ-008`: When an Agent Server performs an orderly stop, the Agent
lifecycle boundary shall emit one `:stop` span over owned cleanup.

`OBS-REQ-009`: When one Signal enters an admitted live Turn, the Agent Turn
boundary shall emit one Turn `:start` event.

`OBS-REQ-010`: When a live Turn reaches a committed result, the Agent Turn
boundary shall emit its terminal span event at that commit point.

`OBS-REQ-011`: When a Turn fails before commit with a returned value, the Agent
Turn boundary shall emit `:stop` with the public failure status.

`OBS-REQ-012`: If a fault escapes a semantic span boundary, then that boundary
shall emit `:exception` with its fault kind before the fault continues.

`OBS-REQ-013`: When a live Turn attempts commit, the Agent commit boundary
shall emit one commit span around the operation that decides whether the
candidate becomes live.

`OBS-REQ-014`: When one post-commit Directive runs, the Agent Directive
boundary shall emit one Directive span.

`OBS-REQ-015`: When an admitted Turn reaches a public terminal Outcome, the
Agent observation boundary shall emit exactly one `turn.settled` event.

`OBS-REQ-016`: When a Turn has post-commit Directive work, the Agent observation
boundary shall emit `turn.settled` after all owned Directive attempts settle.

`OBS-REQ-017`: If abrupt process or VM loss prevents terminal emission, then
Jido shall not reconstruct a terminal semantic event from debug history.

### Admission, persistence, and topology visibility

`OBS-REQ-018`: When a call or cast is rejected before Turn admission, the Agent
admission boundary shall emit one `admission.rejected` event.

`OBS-REQ-019`: When `Jido.Persistence` performs a public load,
compare-and-swap, or delete operation, the persistence boundary shall emit one
persistence span.

`OBS-REQ-020`: When the static local Topology Controller performs activation,
repair, or cleanup, the local Topology boundary shall emit one Topology span.

`OBS-REQ-021`: Where an optional distributed control plane changes membership,
placement, authority, handoff, recovery, or operator state, its package owner
shall emit one event that follows the control-plane metadata contract in this
file.

### Measurements and result meaning

`OBS-REQ-022`: When a semantic span starts, its boundary shall measure both
system time and monotonic time in the Erlang native time unit.

`OBS-REQ-023`: When a semantic span stops or reports an exception, its boundary
shall measure nonnegative duration in the Erlang native time unit.

`OBS-REQ-024`: When a Turn result or settlement event is emitted, the Agent
observation boundary shall include the applicable version and Directive count
measurements from the measurement contract.

`OBS-REQ-025`: When a persistence operation reports revision data, the
persistence boundary shall put numeric revisions in measurements instead of
metric tags.

`OBS-REQ-026`: When admission or Topology events report capacity data, their
boundaries shall put numeric counts in measurements instead of metadata.

### Identity, correlation, and causation

`OBS-REQ-027`: Where the approved Agent Ref exists, when an Agent semantic
event is emitted, the Agent observation boundary shall project its namespace,
partition, and ID as `agent_namespace`, `agent_partition`, and `agent_id`.

`OBS-REQ-028`: During the identity migration interval, when an Agent semantic
event is emitted, the Agent observation boundary shall retain the current
`jido_instance` and `partition` fields when they are valid.

`OBS-REQ-029`: When an admitted Turn event is emitted, the Agent observation
boundary shall include its activation, Turn, source Signal, and effective
Signal identifiers when they apply.

`OBS-REQ-030`: When causal trace data is available, the Agent observation
boundary shall report trace parentage separately from Signal causation.

`OBS-REQ-031`: When Jido sends a Signal across a process or node boundary, Jido
shall use the complete portable W3C carrier owned by `jido_signal`.

`OBS-REQ-032`: When Jido starts an owned Task for observed work, the owning
boundary shall transfer the applicable trace context explicitly.

### Privacy and cardinality

`OBS-REQ-033`: When Jido emits a semantic event, the event boundary shall
include only fields from the metadata contract.

`OBS-REQ-034`: When Jido emits a semantic event, the event boundary shall omit
the excluded private values listed in the metadata contract.

`OBS-REQ-035`: When a semantic event reports an error, its boundary shall use a
bounded projection from the public error contract.

`OBS-REQ-036`: If a metadata value fails its type, UTF-8, or size rule, then the
semantic event boundary shall omit that value without changing the runtime
result.

`OBS-REQ-037`: When Jido returns default metric definitions, Jido shall derive
them from semantic events.

`OBS-REQ-038`: When Jido returns default metric definitions, Jido shall use
only the low-cardinality tags listed in the default consumer contract.

### Logs and failure behavior

`OBS-REQ-039`: Where the semantic logger is enabled, the logger shall support
the modes `:off`, `:errors`, `:interesting`, and `:all`.

`OBS-REQ-040`: When the semantic logger writes an entry, it shall use only the
safe semantic projection and selected measurements.

`OBS-REQ-041`: When a built-in Telemetry handler receives an event, it shall
return without calling the observed Agent or doing direct network or storage
I/O.

`OBS-REQ-042`: If semantic event emission fails, then the emitting boundary
shall preserve the defined command result and runtime Outcome.

`OBS-REQ-043`: If a built-in metrics, logging, or bridge consumer fails, then
that consumer shall not fail the emitting runtime operation.

### OpenTelemetry

`OBS-REQ-044`: Where the optional OpenTelemetry bridge is enabled, the bridge
shall translate only the semantic event catalog.

`OBS-REQ-045`: Where the optional OpenTelemetry bridge is present, the host
application shall own SDK start, sampling policy, exporters, collectors,
credentials, and vendor configuration.

`OBS-REQ-046`: Where the OpenTelemetry API dependency is absent or the bridge
is disabled, Jido shall compile and run without OpenTelemetry startup.

`OBS-REQ-047`: When the OpenTelemetry bridge maps a Turn, the bridge shall
preserve separate live-result and terminal-settlement facts.

`OBS-REQ-048`: When an OpenTelemetry context crosses a Jido-owned Task
boundary, the task owner shall attach and restore that context without leaking
it into later work.

### Compatibility, versioning, and evidence

`OBS-REQ-049`: When a semantic schema change is additive, Jido shall keep the
existing event name and field meanings.

`OBS-REQ-050`: When a semantic schema change is breaking, Jido shall introduce
a new versioned contract with a documented overlap interval.

`OBS-REQ-051`: Until semantic consumers prove replacement coverage, Jido shall
retain legacy Agent Server events, `Jido.Observe`, tracing, logging, and debug
paths.

`OBS-REQ-052`: When the semantic event catalog changes, focused tests shall
prove each start, terminal, point, and ordering rule.

`OBS-REQ-053`: When safe metadata changes, focused tests shall prove the
allowlist, size limits, private-value exclusion, and metric-tag limits.

`OBS-REQ-054`: When correlation behavior changes, focused tests shall prove
local, retry, child-activation, Task, known-node, and concurrent continuity.

`OBS-REQ-055`: Where the OpenTelemetry bridge is implemented, tests shall
prove builds without the API, with API-only no-op behavior, with the bridge
disabled, and with an in-memory SDK.

`OBS-REQ-056`: When a host disables all built-in consumers, the semantic event
boundaries shall continue to emit the event catalog.

`OBS-REQ-057`: When a host configures an old logging or redaction option, the
semantic event boundary shall not broaden its metadata allowlist.

## Invariants

- Observation has no execution or persistence authority.
- A live result and a terminal settlement stay distinct.
- One admitted Turn has at most one observable terminal Outcome.
- A Signal trace carrier and semantic metadata contain correlation, not Agent
  state or payload data.
- Semantic emission failure preserves the runtime result.
- Telemetry is best-effort and is not an audit journal.
- Export and vendor policy stay outside Jido core.

## Open design decisions

| ID | Decision | Recommended answer | Effect if changed |
| --- | --- | --- | --- |
| `OBS-DEC-001` | Event catalog | Approve the eight families in this file. | Names, tests, metrics, logs, and bridge mapping must change together. |
| `OBS-DEC-002` | Agent Ref projection | Use `agent_namespace`, `agent_partition`, and `agent_id`. | Identity migration and attribute names change. |
| `OBS-DEC-003` | Lifecycle operations | Add `hibernate` and `thaw`; keep create/delete under persistence. | Lifecycle and persistence ownership changes. |
| `OBS-DEC-004` | Public statuses and stages | Approve the bounded tables and keep private stages hidden. | Dashboards and compatibility tests change. |
| `OBS-DEC-005` | Default logs | Use four semantic modes and safe fields only. | Configuration migration and coverage gates change. |
| `OBS-DEC-006` | OpenTelemetry owner | Put an optional semantic bridge in Jido core; keep infrastructure in the host. | A separate package needs a public attachment and version contract. |
| `OBS-DEC-007` | OpenTelemetry Turn span end | Select live result or settlement before bridge work starts. | Span duration and settlement mapping change. |
| `OBS-DEC-008` | Legacy overlap | Remove nothing until inventory, parity tests, notice, and review are complete. | Earlier removal is a breaking change. |

## Downstream guarantees

- Operators can distinguish evaluation failure, commit failure, committed
  post-effect failure, admission rejection, persistence failure, and Topology
  degradation without reading private state.
- A reporter can join Agent work by Ref, activation, Turn, Signal, trace, and
  causation without using a PID as identity.
- Hosts can use Telemetry only, attach the optional OpenTelemetry bridge, or
  export copied events through another process.
- A distributed control plane can use the same safety rules without moving its
  authority model into Jido core.
