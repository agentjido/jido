# Jido V3 observability alignment

## Status

Pending approval.

This review uses Jido commit
`f7633a69f081e8336647114b20b941fb2f64d438` from 2026-09-08 as the code
baseline. The working tree also contains an unrelated user change in
`examples/04_runtime/04_09_agent_observation/event_probe.ex`. This seam does not
change that file.

The code is the canonical record of current behavior. [design.md](design.md)
is the pending target contract. This file defines evidence, gaps, and gates. It
is not a formal implementation plan.

## Inputs and evidence

### Design inputs

The README, design, and alignment documents were reviewed for every
prerequisite seam below.

| Input | Contract used here |
| --- | --- |
| [00 Core model](../00_overview/alignment.md) | Direct evaluation has no Agent runtime event. The live result, settlement, privacy, observer-failure, and compatibility invariants stay separate. |
| [90 Package boundaries](../90_package-boundaries/alignment.md) | Jido owns semantic Agent observation. Lower packages own their execution and Signal contracts. Hosts own vendor infrastructure. |
| [12 Errors and contracts](../12_errors-and-contracts/alignment.md) | Current error map version 1 stays supported. Target error version 2 is pending. Telemetry can use a smaller safe projection. |
| [01 Agent](../01_agent/alignment.md) | An Agent is a pure value. Direct `cmd/3` does not make a live commit. |
| [03 Agent identity](../03_agent-identity/alignment.md) | Target correlation identity is the complete Agent Ref namespace, partition, and ID. The Ref is not implemented. |
| [04 Turn evaluation](../04_turn-evaluation/alignment.md) | Public observation must not make private evaluation stages or Plugin callbacks stable. |
| [05 Plugins](../05_plugins/alignment.md) | Plugin state is private. The Agent Server owns observed Plugin tasks; `jido_action` owns execution telemetry. |
| [06 Commit and effects](../06_commit-and-effects/alignment.md) | Commit makes the candidate live after required persistence. Directive work is post-commit and can fail later. |
| [07 Persistence](../07_persistence/alignment.md) | Jido owns Agent record meaning and uses byte adapters. Conflict and uncertain-write meanings must stay exact. |
| [08 Agent Server](../08_agent-server/alignment.md) | One admitted Turn produces a public Outcome. Caller reply can occur before settlement. |
| [09 Jido instance](../09_jido-instance/alignment.md) | Current instances are module identities, not namespaces. The instance owns local runtime services and persistence context. |
| [10 Runtime topology](../10_runtime-topology/alignment.md) | The current tree is local and static. Owned tasks, known-node children, and cleanup need bounded correlation. |
| [11 Topology control plane](../11_topology-control-plane/alignment.md) | Distributed control is optional and external. Its owner must report bounded membership, placement, authority, handoff, recovery, and operator facts. |
| [Vision](../VISION.md) | Jido includes semantic telemetry, not vendor infrastructure. Observation failure preserves the result. |

### Canonical code

| Evidence | Current fact |
| --- | --- |
| `lib/jido/telemetry.ex:8-30` | Public module text lists semantic lifecycle, Turn, commit, Directive, and settlement events. It also states that old Agent Server events remain. |
| `lib/jido/telemetry/agent.ex:8-44` | Semantic identity uses Agent ID, module, activation ID, Jido instance, partition, Turn and Signal IDs, and selected trace fields. |
| `lib/jido/telemetry/agent.ex:46-93` | Semantic spans use native monotonic and system times. Returned values stop a span. Escaping faults emit exceptions and continue. |
| `lib/jido/telemetry/agent.ex:96-147` | A successful Turn span stops at commit. `turn.settled` reports versions and Directive counts after terminal Outcome. |
| `lib/jido/telemetry/agent.ex:163-223` | Error metadata contains type and retryability. The metadata allowlist has size checks. Event emission catches handler faults. |
| `lib/jido/agent_server.ex:493-544` | Activation observation starts during Server initialization and stops after Plugin readiness. |
| `lib/jido/agent_server.ex:1285-1322` | Turn start establishes Signal trace context before it emits semantic Turn start. |
| `lib/jido/agent_server.ex:1493-1545` | Commit observation wraps persistence. The live Agent and caller reply occur before post-commit settlement. |
| `lib/jido/agent_server.ex:1926-1978` | Expired and overloaded work can be rejected before admission. Cast overload writes a log, but no semantic rejection event exists. |
| `lib/jido/agent_server.ex:2618-2639` | Terminal Outcome causes `turn.settled`; debug history is recorded separately. |
| `lib/jido/agent_server.ex:2659-2747` | Old Agent Server spans and new semantic Directive spans run together. Jido contains faults from both paths at this runtime call site. |
| `lib/jido/agent_server.ex:2887-2948` | Activation, commit, and shutdown call persistence without a semantic persistence event family. |
| `lib/jido/agent/turn/outcome.ex:1-67` | Outcome has five statuses, five detailed stages, source and effective Signals, versions, error, Directive summary, and timing. Semantic telemetry projects a smaller view. |
| `lib/jido/persistence.ex:1-16,59-150` | Persistence owns records and public load, compare-and-swap save, and delete operations. It emits no semantic events. |
| `lib/jido/topology/controller.ex:1-24,43-90` | The Controller owns fixed-target local activation and repair. It emits no semantic Topology events. |
| `lib/jido/tracing/trace.ex:1-47` | New roots contain legacy IDs and a W3C carrier. New roots currently use fixed W3C flags `00`. |
| `lib/jido/tracing/trace.ex:50-125` | Trace helpers read and write complete legacy and W3C representations. Semantic telemetry receives the legacy-shaped IDs, not `tracestate`. |
| `lib/jido/tracing/context.ex:1-127` | Trace context is process-local. Signal propagation is explicit. It does not move automatically into a Task. |
| `lib/jido/telemetry.ex:63-125` | Application startup attaches the old log consumer. `metrics/0` returns three metrics based on old Agent Server events. |
| `lib/jido/observe.ex:1-98` | `Jido.Observe` is a public façade over Telemetry and tracer callbacks. Async spans are explicit and context-neutral. |
| `lib/jido/observe/config.ex:17-41,180-240` | Current configuration has log levels, log argument modes, debug modes, redaction, a tracer, and a strict tracer-failure option. |
| `lib/jido/application.ex:1-9` | Jido attaches its current Telemetry handler on application start. |
| `mix.exs`; `mix.lock` | Jido has no OpenTelemetry dependency. |

### Public documentation and examples

| Evidence | Current fact |
| --- | --- |
| `guides/telemetry-tracing-and-logs.md` | The guide documents semantic events, old events, `Jido.Observe`, process-local tracing, logs, and synchronous-handler limits. |
| `guides/observability.md` | The guide distinguishes telemetry from status, debug history, and durable audit data. Its admission wording is broader than current semantic evidence. |
| `guides/observe-agent-turns.livemd` | The example attaches to `turn.settled` and treats it as the public terminal fact. |
| `examples/04_runtime/04_09_agent_observation/turn_observation.ex` | The example shows a committed success and a committed post-Directive failure. |
| `examples/04_runtime/04_09_agent_observation/causal_trace.ex` | The example shows trace, parent, causation, Turn, and child-activation correlation. |

### Focused tests

| Evidence | Current proof |
| --- | --- |
| `test/jido/observe/agent_lifecycle_test.exs:10-45` | Direct evaluation emits no Agent runtime events. A failing external handler does not change a live command result. |
| `test/jido/observe/agent_lifecycle_test.exs:48-119` | Five admitted Turn Outcomes each have one matching terminal semantic event with safe projected fields. |
| `test/jido/observe/agent_lifecycle_test.exs:121-228` | Activation, restart, stop, commit, Directive, and settlement event order is proved. |
| `test/jido/observe/agent_lifecycle_test.exs:230-302` | Semantic events exclude private data and raw errors. Directive timeout remains a committed terminal Outcome. |
| `test/jido/observe/agent_lifecycle_test.exs:308-384` | Requested stop and Directive task crash each produce one bounded terminal Outcome when the process can emit it. |
| `test/jido/telemetry/agent_test.exs:21-104` | Error projection, status mapping, size limits, allowlist behavior, and start measurements are proved. |
| `test/jido/observe/causal_trace_test.exs:260-288` | Retry correlation preserves trace and causation while creating a new Turn and span. |
| `test/jido/observe/remote_causal_trace_test.exs:130-175` | Known-node child activation and failed remote creation preserve bounded causal identity. |
| `test/jido/tracing/trace_test.exs`; `test/jido/tracing/context_test.exs` | Complete legacy/W3C carrier validation and explicit process-local propagation are proved. |
| `test/jido/telemetry_test.exs` | The three old metric definitions and old log consumer behavior are proved. |
| `test/jido/observe/failure_and_config_test.exs:30-99` | Warn mode contains tracer failures. The retained strict mode can raise from a tracer callback. |

## Retained baseline

- Semantic Telemetry is the target source for Jido runtime observation.
- Current lifecycle `activate` and `stop` spans remain valid.
- The Turn span starts at admission and ends at the live result. It does not
  include later Directive settlement time.
- Commit and each Directive are separate spans.
- `turn.settled` reports one terminal Outcome after Directive work when the
  running process can emit it.
- Returned failures use `:stop`; escaping faults use `:exception`.
- Current semantic measurements use native time units and integer revisions
  and counts.
- Current semantic metadata is allowlisted and excludes state, payloads, raw
  errors, stacktraces, and process handles.
- Legacy Agent Server events, `Jido.Observe`, trace helpers, logs, and debug
  history remain supported during migration.
- Signal trace propagation carries both legacy and W3C forms. The W3C form is
  the portable target carrier.
- Telemetry is best-effort. It is not durable audit evidence.

## Gap register

| ID | Requirements | Current evidence | Gap | Disposition |
| --- | --- | --- | --- | --- |
| `OBS-GAP-001` | `OBS-REQ-006` to `OBS-REQ-008` | Lifecycle emits only activate and stop. | Hibernate and thaw do not have distinct semantic lifecycle spans. | `Target addition`; pending `OBS-DEC-003` |
| `OBS-GAP-002` | `OBS-REQ-018` | Calls return admission timeout or overload; cast overload only logs. | No semantic admission-rejection event exists. | `Target addition` |
| `OBS-GAP-003` | `OBS-REQ-019`, `OBS-REQ-025` | Persistence has public load, CAS, and delete operations. | No semantic persistence span or revision measurement contract exists. | `Target addition` |
| `OBS-GAP-004` | `OBS-REQ-020`, `OBS-REQ-026` | Static local Controller status and repair exist. | No semantic local Topology event exists. | `Target addition` |
| `OBS-GAP-005` | `OBS-REQ-021` | Seam 11 specifies bounded control-plane facts. | No distributed control-plane package or events exist. | `External and optional`; do not implement in core |
| `OBS-GAP-006` | `OBS-REQ-027`, `OBS-REQ-028` | Current identity is instance, partition, and ID. | Agent Ref and namespace are not implemented; target field names are not approved. | `Blocked` on seam 03 and `OBS-DEC-002` |
| `OBS-GAP-007` | `OBS-REQ-030` to `OBS-REQ-032` | Signal carrier and causal metadata work across tested local and known-node paths. | Jido-owned Tasks do not have one explicit OpenTelemetry context-transfer contract. | `Partial`; add owner-bound transfer tests |
| `OBS-GAP-008` | `OBS-REQ-033` to `OBS-REQ-036` | Agent semantic events have a strict allowlist. | New event families and older `Jido.Observe` paths do not share this projection. | `Partial`; apply contract only to semantic families |
| `OBS-GAP-009` | `OBS-REQ-035` | Current semantic projection has error type and retryability. | Target error class and code depend on pending error map version 2. | `Blocked` on seam 12 migration |
| `OBS-GAP-010` | `OBS-REQ-037`, `OBS-REQ-038` | Three old Agent Server metrics exist. | No default metric uses the semantic catalog. Current metrics tag `jido_instance`. | `Replace after parity`; do not remove first |
| `OBS-GAP-011` | `OBS-REQ-039`, `OBS-REQ-040` | The old log consumer and configuration work. | No semantic logger or four-mode semantic policy exists. | `Replace after parity` |
| `OBS-GAP-012` | `OBS-REQ-041` to `OBS-REQ-043` | Agent semantic emission and Agent Server wrappers contain observer faults. | Public `Jido.Observe` strict mode can still make a tracer failure visible to its caller. | `Compatibility exception`; do not use strict mode for semantic runtime emission |
| `OBS-GAP-013` | `OBS-REQ-044` to `OBS-REQ-048`, `OBS-REQ-055` | No dependency or bridge exists. | Package owner, Turn span end, context transfer, and compile matrix are unresolved. | `Target optional`; pending decisions 006 and 007 |
| `OBS-GAP-014` | `OBS-REQ-049`, `OBS-REQ-050` | Current semantic names have no schema version field. | Additive and breaking change rules have no executable schema-version proof. | `Target addition` |
| `OBS-GAP-015` | `OBS-REQ-051` | Old and semantic paths run together. | No consumer inventory, parity report, notice period, or removal approval exists. | `Retain`; removal is blocked |
| `OBS-GAP-016` | `OBS-REQ-052` to `OBS-REQ-057` | Focused Agent event and causal tests pass. | Missing families, metrics, logs, Task context, schema evolution, and bridge modes have no tests. | `Partial`; close with each target addition |
| `OBS-GAP-017` | Documentation integration | Main design review table and seam 99 | The review table links to three removed files. The delivery gap analysis cites the removed bridge file. | `Blocked` by this task's folder-only edit limit |

## Disposition of superseded claims

This table accounts for the distinct design claims in the removed
`gap-analysis.md`, `observability.md`, and `opentelemetry-bridge.md` files.

| Superseded claim | Disposition | Reason |
| --- | --- | --- |
| Lifecycle, Turn, commit, Directive, and settlement events exist. | `Retain as current`. | Code and focused tests prove them. |
| Add Agent create and delete lifecycle events. | `Replace`. | Record creation and deletion belong to persistence operations. They are not live activation facts. |
| Add hibernate and thaw lifecycle operations. | `Retain as target`. | They are real lifecycle boundaries if decision 003 is approved. |
| Add route, before-Plugin, after-Plugin, or each Plugin callback events. | `Reject`. | These are private evaluation details and would freeze internal stages. |
| Add one admission-rejected point event. | `Retain as target`. | Rejected work never has a Turn start or Outcome. |
| Add persistence operation spans. | `Retain as target`. | The public load, CAS, and delete boundary has no semantic visibility. |
| Treat `turn.stop` as terminal settlement. | `Reject`. | A successful Turn stops at live commit; settlement can fail later. |
| Keep commit and Directive spans separate from the Turn result. | `Retain`. | This matches current ordering and commit semantics. |
| Report one terminal settlement event for each admitted Turn. | `Retain with limit`. | The running process emits one when possible; abrupt loss can omit it. |
| Claim direct Agent evaluation has no telemetry at all. | `Clarify`. | It has no Agent runtime event. A lower execution package can emit its own events. |
| Use `jido_namespace` as logical identity. | `Replace`. | Use explicit Agent Ref projection fields `agent_namespace`, `agent_partition`, and `agent_id`. |
| Keep `jido_instance` as the permanent namespace. | `Reject as target`. | A current instance module is not the target Agent namespace. Keep it only for overlap. |
| Put `traceparent` and `tracestate` in every semantic event. | `Replace`. | Keep the complete carrier on Signals. Exclude `tracestate` from semantic metadata and expose bounded trace IDs. |
| Report write authority on core Agent events. | `Move to owner`. | Authority does not exist in current core. An optional control-plane owner reports its own authority facts. |
| Use public statuses and only evaluate, commit, and Directive stages. | `Retain and refine`. | The new tables include persistence, admission, and topology results without exposing private evaluator stages. |
| Use native time, revision, and Directive-count measurements. | `Retain`. | Current Agent semantic events already use these units and shapes. |
| Publish a large default metric catalog immediately. | `Right-size`. | First add count and duration coverage for each semantic family, then add only proven operational metrics. |
| Add semantic logger modes false, errors, interesting, and all. | `Replace names`. | Use `:off`, `:errors`, `:interesting`, and `:all` for one atom-based configuration. |
| Remove the old log handler after semantic logger work. | `Defer`. | Parity, migration notice, and approval are missing. |
| Remove `Jido.Observe`, tracing, and debug paths in V3. | `Reject now`. | Prerequisite seams require them to remain until equal coverage and an approved migration exist. |
| Broaden the semantic metadata type to arbitrary values. | `Reject`. | The public `Jido.Telemetry` type is broader than the target safe semantic contract. |
| Reserve an opaque `telemetry_span_context` reference in public metadata. | `Reject`. | References are not portable semantic data. A bridge must keep its private span state outside the event contract. |
| Remove the Agent Server debug timeline as part of observability alignment. | `Reject now`. | Debug history is a supported diagnostic path and prerequisite seams require a separate migration. |
| Prevent users from disabling redaction on all old observation APIs. | `Replace`. | New semantic events use a strict allowlist. Current broad APIs keep their compatibility behavior until migration. |
| Put an optional OpenTelemetry bridge in Jido core. | `Retain as recommendation`. | It keeps semantic mapping near its owner and vendor infrastructure in the host. Approval is pending. |
| Pin one OpenTelemetry API version in the design. | `Defer`. | Dependency selection is implementation evidence and can change before approval. |
| Fix the public bridge API as `available?/0` and `enabled?/0`. | `Defer API shape`. | Explicit host enablement is required, but implementation review must prove the smallest public surface. |
| Auto-start OpenTelemetry when a dependency is available. | `Reject`. | Availability is not host intent. Enablement and SDK start must be explicit. |
| Use semantic Telemetry as the only OpenTelemetry source. | `Retain`. | This avoids duplicate spans from old events and tracer callbacks. |
| Keep one OpenTelemetry Turn span open through settlement. | `Open decision`. | It improves total-latency display but differs from the semantic live-result span end. Both facts must stay separate. |
| Let the OpenTelemetry SDK create the root sampling decision before Signal tracing. | `Reject as a core rule`. | The host owns sampling. Signals must still carry a complete portable context when Jido creates a root. |
| Copy process-local context implicitly into every Task. | `Replace`. | Each task owner must explicitly attach and restore context. Lower packages own their task boundaries. |
| Put durable trace storage in Jido telemetry. | `Reject`. | The Signal is the portable carrier. A durable queue or orchestrator owns storage of that carrier. |
| Retire a `jido_otel` package as part of this change. | `Defer to inventory`. | The repository has only a future-package note. No installed package or consumer evidence was found. |
| Add AI model, tool, token, or Langfuse mappings to core. | `Move to owner`. | These facts belong to `jido_ai` or the host. |
| Emit distributed placement and authority events from current Jido core. | `Move to control-plane owner`. | Current core has only static local Topology. |
| Perform exporter work in a Telemetry handler. | `Reject`. | Handlers are synchronous. They must hand off bounded data without direct network or storage I/O. |
| Prove no-API, disabled, SDK, exporter, and concurrent bridge modes. | `Retain and stage`. | No-API, disabled, and in-memory SDK are core gates. Exporter and vendor tests belong to host integrations. |
| Use privacy and observer-failure matrices as acceptance evidence. | `Retain`. | These matrices protect behavior across every semantic family. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.

### Phase 0 — Approve the contract

- Required outcome: approve or change the eight decisions in
  [design.md](design.md).
- Gate: Agent Ref, error projection, lifecycle operations, event names, log
  modes, OpenTelemetry owner, Turn span end, and compatibility policy have one
  recorded answer.

### Phase 1 — Freeze current semantic behavior

- Required outcome: public module text, guides, examples, and focused tests use
  the same current event meanings and safe-field rules.
- Gate: direct evaluation, live-result timing, settlement timing, returned
  failure, escaping fault, handler failure, and causal correlation stay green.

### Phase 2 — Close owned event gaps

- Required outcome: admission rejection, persistence operations, local
  Topology operations, approved lifecycle operations, schema version, and Agent
  Ref projection have bounded semantic evidence.
- Gate: each new family has catalog, privacy, failure, ordering, and owner tests.

### Phase 3 — Move default consumers

- Required outcome: default metrics and logs use semantic events and give equal
  or better operational coverage than the old consumers.
- Gate: metric cardinality, log safety, configuration migration, and failure
  isolation tests pass while old consumers remain available.

### Phase 4 — Add optional OpenTelemetry translation

- Required outcome: the approved bridge maps the semantic catalog and transfers
  context at Jido-owned Task boundaries without owning vendor infrastructure.
- Gate: no-API, disabled, in-memory SDK, timing, privacy, error, concurrency,
  and context-cleanup tests pass.

### Phase 5 — Decide deprecation

- Required outcome: a consumer inventory and parity report identify every old
  event, callback, configuration key, log path, tracing helper, and debug use.
- Gate: removal needs notice, a major-version policy, and separate approval.

## Acceptance matrix

| Requirements | Current evidence | Required acceptance | State |
| --- | --- | --- | --- |
| `OBS-REQ-001` to `OBS-REQ-005` | Semantic catalog and package boundaries exist. | Catalog and ownership review | `Partial` |
| `OBS-REQ-006` to `OBS-REQ-008` | Activate and stop are proved. | Hibernate and thaw lifecycle tests | `Partial` |
| `OBS-REQ-009` to `OBS-REQ-016` | Agent lifecycle focused tests prove Turn, commit, Directive, settlement, and ordering. | Keep the full success and failure matrix green | `Proven for current paths` |
| `OBS-REQ-017` | Public module text states that abrupt loss can omit events. | Crash and VM-loss documentation check | `Documented` |
| `OBS-REQ-018` | Admission returns and one cast log exist. | Call, cast, deadline, overload, and privacy tests | `Missing` |
| `OBS-REQ-019` | Public persistence operations exist. | Load, not-found, CAS success, conflict, indeterminate, error, delete, and fault tests | `Missing` |
| `OBS-REQ-020` | Static local Controller operations exist. | Activate, repair, degraded, cleanup, and failure tests | `Missing` |
| `OBS-REQ-021` | Seam 11 target only | Provider-owned event and failure matrix | `External; missing` |
| `OBS-REQ-022` to `OBS-REQ-024` | Current Agent event measurement tests | Extend exact measurement tests to each result class | `Partial` |
| `OBS-REQ-025`, `OBS-REQ-026` | No matching semantic families | Numeric measurement and no-tag tests | `Missing` |
| `OBS-REQ-027` | Ref target only | Complete Ref projection and bound tests | `Blocked` |
| `OBS-REQ-028` to `OBS-REQ-030` | Current identity and causal tests | Overlap and field-meaning tests | `Partial` |
| `OBS-REQ-031` | Trace and remote causal tests | Keep complete carrier tests green | `Proven for tested paths` |
| `OBS-REQ-032` | Explicit Signal propagation; no full Task contract | Task attach, restore, exception, cancellation, and reuse tests | `Partial` |
| `OBS-REQ-033` to `OBS-REQ-036` | Agent semantic allowlist and privacy tests | Apply the matrix to each new family | `Partial` |
| `OBS-REQ-037`, `OBS-REQ-038` | Metrics use old events | Semantic definition and cardinality tests | `Missing` |
| `OBS-REQ-039`, `OBS-REQ-040` | Old log policy only | Four modes, safe output, threshold, and configuration tests | `Missing` |
| `OBS-REQ-041` to `OBS-REQ-043` | Semantic emission containment tests; retained strict tracer mode | Consumer fault and no-I/O architecture tests | `Partial` |
| `OBS-REQ-044` to `OBS-REQ-048` | No bridge | Semantic-only mapping, ownership, timing, and context tests | `Missing` |
| `OBS-REQ-049`, `OBS-REQ-050` | No schema version | Additive and breaking-fixture compatibility tests | `Missing` |
| `OBS-REQ-051` | Old and semantic paths coexist | Inventory, parity report, notice, and review | `Retained; removal blocked` |
| `OBS-REQ-052` to `OBS-REQ-054` | Current focused event and correlation suite | Extend it with every target family and Task boundary | `Partial` |
| `OBS-REQ-055` | No dependency or bridge | Four-mode compile and runtime matrix | `Missing` |
| `OBS-REQ-056`, `OBS-REQ-057` | Current Agent semantic emitter ignores consumer and redaction settings. | Keep independence and allowlist tests green for every family | `Proven for current Agent events` |

## Migration and compatibility

1. Add new semantic families without changing current Agent event names or
   meanings.
2. Add `schema_version` and Agent Ref projection fields as additive metadata.
   Keep valid `jido_instance` and `partition` fields for the approved overlap.
3. Keep `trace_id`, `span_id`, `parent_span_id`, and `causation_id` meanings
   stable. Do not expose `tracestate` as general Telemetry metadata.
4. Add semantic metric and log consumers beside the old consumers. Provide a
   configuration map from current log levels and argument modes to the new
   semantic modes.
5. Keep OpenTelemetry disabled unless the host explicitly enables it. The
   absence of its API must remain a supported build.
6. Do not make `Jido.Observe` strict tracer mode part of the semantic Agent
   runtime path. Keep its current public behavior until a separate migration is
   approved.
7. Before deprecation, publish an inventory, parity evidence, replacement
   examples, notice interval, and rollback path.
8. Remove an old path only in the release allowed by the approved compatibility
   policy.

## Assumptions and blockers

| ID | Type | Dependency | Statement | Required resolution |
| --- | --- | --- | --- | --- |
| `OBS-BLK-001` | `Decision` | This seam | The eight event families are the target catalog. | Approve or change `OBS-DEC-001`. |
| `OBS-BLK-002` | `Blocker` | 03 Agent identity | `%Jido.Agent.Ref{}` and target namespace are not implemented. | Approve seam 03 and field names in `OBS-DEC-002`. |
| `OBS-BLK-003` | `Decision` | 07, 08, 13 | Hibernate and thaw are distinct lifecycle operations; create/delete are persistence facts. | Approve or change `OBS-DEC-003`. |
| `OBS-BLK-004` | `Decision` | 04, 06, 08, 13 | The bounded status and stage tables are the public observation vocabulary. | Approve or change `OBS-DEC-004`. |
| `OBS-BLK-005` | `Blocker` | 12 Errors | Error class and code depend on error map version 2. | Approve the error migration before these fields become required. |
| `OBS-BLK-006` | `Decision` | This seam | Semantic log modes replace current consumer configuration only after parity. | Approve or change `OBS-DEC-005`. |
| `OBS-BLK-007` | `Decision` | 13 and host | An optional bridge belongs in Jido; the host owns OpenTelemetry infrastructure. | Approve or change `OBS-DEC-006`. |
| `OBS-BLK-008` | `Decision` | 06, 08, 13 | The OpenTelemetry Turn span end is unresolved. | Select live result or settlement in `OBS-DEC-007`. |
| `OBS-BLK-009` | `Blocker` | Compatibility owners | There is no old-consumer inventory or parity report. | Complete both before any deprecation proposal. |
| `OBS-BLK-010` | `Decision` | Release policy | The overlap and removal policy is pending. | Approve or change `OBS-DEC-008`. |
| `OBS-BLK-011` | `Assumption` | 11 Control plane | An optional control-plane package owns distributed event names and emission. | Confirm when that package is selected. |
| `OBS-BLK-012` | `Blocker` | Design index and seam 99 | The main review table and delivery gap analysis still refer to removed seam files. This task permits edits only in this folder. | Update those references in separate owner-scoped edits. |

## Verification record

On 2026-09-08, the focused current-behavior suite passed at the recorded code
baseline:

```text
mix test test/jido/telemetry/agent_test.exs \
  test/jido/telemetry_test.exs \
  test/jido/tracing/trace_test.exs \
  test/jido/tracing/context_test.exs \
  test/jido/observe/agent_lifecycle_test.exs \
  test/jido/observe/causal_trace_test.exs \
  test/jido/observe/remote_causal_trace_test.exs --seed 0

61 passed
```

This result proves only current behavior. It does not prove a target addition.

## Completion criteria

This seam is complete for release review when:

- all eight decisions have approved answers;
- every requirement has direct test or review evidence;
- the Agent Ref and safe error projections are available or their fields are
  explicitly deferred;
- admission, persistence, and local Topology event gaps are closed;
- semantic metrics and logs pass safety and parity gates;
- any OpenTelemetry bridge passes its optional build and runtime matrix;
- the compatibility inventory and deprecation record are complete;
- public guides, examples, module text, and the main review table link only to
  current seam documents; and
- observation failure cannot change any defined result or Outcome.
