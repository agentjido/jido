> Implemented seam alignment. This record maps the selected observation
> contract to its owners, compatibility rules, and evidence.

# Jido V3 observability alignment

## Status

- Contract selected and implemented: 2026-09-10.
- Alignment state: `Implemented`.
- Compatibility state: breaking V3 cleanup. Legacy Agent Server telemetry and
  `Jido.Observe` are removed. Semantic telemetry is the single source.
- OpenTelemetry state: Core has an API-only optional mapping. The host owns the
  SDK, exporter, collector, network, credentials, resources, and vendor policy.
- Follow-on work: seam 99 owns the final documentation, package, and release
  gate.

## Selected decisions

| ID | Decision | Result |
| --- | --- | --- |
| `OBS-DEC-001` | Use the eight semantic families in the design. | Agent, admission, persistence, and local Topology owners emit them. |
| `OBS-DEC-002` | Project Agent Ref as `agent_namespace`, `agent_partition`, and `agent_id`. | Namespaced Agent events include all applicable Ref fields. |
| `OBS-DEC-003` | Use lifecycle operations `activate`, `stop`, `hibernate`, and `thaw`. | Record creation and deletion remain persistence operations. |
| `OBS-DEC-004` | Use the bounded status and stage vocabularies. | Private evaluator and Plugin callback stages stay internal. |
| `OBS-DEC-005` | Use semantic log modes `off`, `errors`, `interesting`, and `all`. | Log input passes through the semantic allowlist again. |
| `OBS-DEC-006` | Keep an API-only optional mapping in Core and all SDK infrastructure in the host. | The semantic catalog directly creates spans when an SDK tracer is active. |
| `OBS-DEC-007` | End the Turn span at the live result. | `turn.settled` is a zero-duration span linked to the completed Turn. |
| `OBS-DEC-008` | Remove legacy observation paths before V3 release. | V3 has one source for telemetry, logs, metrics, and optional traces. |

## Owner alignment

| Owner | Semantic boundary | Implementation |
| --- | --- | --- |
| Shared | Schema, metadata, measurements, result class, error code, and safe emission | `Jido.Telemetry.Semantic` |
| Agent Server | Lifecycle, Turn, commit, Directive, settlement, and admission rejection | `Jido.Telemetry.Agent` and `Jido.AgentServer` |
| Persistence | Load, compare-and-swap, delete, storage reason, and revisions | `Jido.Telemetry.Persistence` and `Jido.Persistence` |
| Local Topology | Activation, repair, cleanup, readiness counts, and failure counts | `Jido.Telemetry.Topology` and `Jido.Topology.Controller.Runtime` |
| Signal | Complete portable W3C trace carrier | `Jido.Signal.Trace` through `Jido.Tracing.Trace` |
| Task owner | Explicit process-local trace attach and restore | `Jido.Tracing.Context.with_context/2` at Jido-owned Task starts |
| Default consumers | Semantic metrics and bounded logger | `Jido.Telemetry` |
| Optional trace mapping | Semantic spans, safe attributes, error status, links, and W3C context | `Jido.Telemetry.OpenTelemetry` |
| Host | Reporters, OpenTelemetry SDK, sampling, exporters, collectors, credentials, dashboards, and alerts | Outside Jido Core |

## Event and result alignment

| Family | Operations or terminal facts | Status and measurement rule |
| --- | --- | --- |
| Lifecycle | `activate`, `stop`, `hibernate`, `thaw` | Span status plus native duration |
| Turn result | Live commit or pre-commit failure | Public status, public stage, revisions, and Directive count |
| Commit | One commit attempt | Status, expected and live revisions, and Directive count |
| Directive | One post-commit attempt | Status, Directive index, and native duration |
| Settlement | One public terminal Outcome | Public status and stage, commit flag, revisions, Directive summary, and total duration |
| Admission | `deadline_expired` or `overloaded` | Rejected status with queue depth and finite limit |
| Persistence | `load`, `compare_and_swap`, `delete` | `ok`, `error`, `conflict`, `indeterminate`, `not_found`, or `rejected`; revisions are measurements |
| Local Topology | `activate`, `repair`, `cleanup` | `ok` or `error`; component, ready, and failed counts are measurements |

A returned failure emits `:stop`. An escaping error, throw, or exit emits
`:exception`. A handler fault is contained. Abrupt process or VM loss can omit
a terminal event. Jido does not rebuild missing facts from debug history.

## Safe data alignment

All semantic events have `schema_version: 1`. The shared boundary accepts only:

- bounded Agent Ref, runtime, Turn, Signal, trace, topology, and node IDs;
- approved module fields, Boolean fields, statuses, stages, operations, and
  error codes;
- current `jido_instance` and safe `partition` overlap fields; and
- approved integer time, revision, count, and capacity measurements.

The boundary omits invalid UTF-8, oversized strings, nested values, Agent and
Plugin state, Signal and Directive data, caller context, checkpoints, records,
encoded keys, raw errors, error details, error messages, stacktraces, PIDs,
ports, references, functions, actor data, application metadata, and
OpenTelemetry `tracestate`.

`Jido.Error.code/1` supplies `error_code` only for a registered Jido code.
`Jido.Error.to_map/1` supplies the bounded error type and retry flag. The
semantic contract does not change the exact error projection version 1.

## Identity and causation

- `agent_namespace`, `agent_partition`, and `agent_id` identify one logical
  Agent Ref when the namespace and partition apply.
- `activation_id` identifies one live activation.
- `turn_id` identifies one admitted Turn.
- source and effective Signal IDs remain distinct.
- trace parentage and Signal causation remain distinct.
- the Signal holds the complete portable W3C carrier across process, node,
  queue, and durable boundaries.
- Jido-owned Tasks attach a captured process context and restore the earlier
  context after success, error, throw, or exit.

## Default consumer alignment

`Jido.Telemetry.metrics/0` returns count and duration coverage for semantic
lifecycle, Turn result, settlement, commit, Directive, persistence, and local
Topology events, plus an admission-rejection count. Its tags use only fixed
operation, status, stage, reason, and component vocabularies.

The semantic logger reads `semantic_log_mode` from `config :jido, :telemetry`:

| Mode | Terminal facts logged |
| --- | --- |
| `:off` | None |
| `:errors` | Non-OK stops, exceptions, and rejected admission |
| `:interesting` | Error facts and operations over `semantic_slow_threshold_ms` |
| `:all` | Every terminal semantic fact |

Per-instance debug mode takes priority over this value. `:on` selects
`:interesting`, and `:verbose` selects `:all`. The logger filters the event
again and does no Agent call, storage call, or network call.

When the host declares `opentelemetry_api` and starts an SDK tracer, the same
semantic boundaries create OpenTelemetry spans. Without the optional API or an
SDK tracer, this path is a no-op.

## Compatibility and versioning

- Additive version-1 fields keep the event name and existing field meaning.
- A breaking change needs a new versioned contract and an overlap period.
- The pre-release V3 change removes `Jido.Observe`, old Agent Server events,
  their log handler, legacy metrics, and old observation configuration.
- Current W3C tracing helpers and bounded debug history remain available.

## Requirement evidence

| Requirements | Evidence | State |
| --- | --- | --- |
| `OBS-REQ-001` to `OBS-REQ-005` | Shared catalog, owner modules, direct-evaluation and handler-failure tests | `Proven` |
| `OBS-REQ-006` to `OBS-REQ-017` | Agent lifecycle, live-result, Directive, settlement, fault, hibernate, and thaw tests | `Proven` |
| `OBS-REQ-018` | Call, cast, overload, deadline, count, and privacy tests | `Proven` |
| `OBS-REQ-019`, `OBS-REQ-025` | Persistence operation, status, revision, and privacy tests | `Proven` |
| `OBS-REQ-020`, `OBS-REQ-026` | Topology activation, repair, cleanup, status, and count tests | `Proven` |
| `OBS-REQ-021` | Distributed control plane remains external and optional | `Owner-deferred` |
| `OBS-REQ-022` to `OBS-REQ-024` | Shared time normalization and Agent measurement tests | `Proven` |
| `OBS-REQ-027` to `OBS-REQ-032` | Ref projection, causal trace, known-node, and explicit Task context tests | `Proven for Core-owned paths` |
| `OBS-REQ-033` to `OBS-REQ-036` | Shared allowlist, error code, size, UTF-8, and private-data tests | `Proven` |
| `OBS-REQ-037` to `OBS-REQ-040` | Semantic metric-tag and four-mode logger tests | `Proven` |
| `OBS-REQ-041` to `OBS-REQ-043` | Emission and consumer-failure containment tests and no-authority review | `Proven` |
| `OBS-REQ-044` to `OBS-REQ-048`, `OBS-REQ-055` | API-only tracer tests cover safe mapping, span end, settlement link, W3C extraction and injection, Task transfer, disabled mode, and no SDK ownership. A clean no-optional-dependency build covers absence. | `Proven` |
| `OBS-REQ-049` to `OBS-REQ-051` | Schema version 1 and explicit pre-release V3 removal | `Proven` |
| `OBS-REQ-052` to `OBS-REQ-054`, `OBS-REQ-056`, `OBS-REQ-057` | Focused catalog, privacy, correlation, disabled-consumer, and optional-integration tests | `Proven` |

## Verification record

- Focused OpenTelemetry, semantic lifecycle, local and remote causal trace, and
  instance-option tests: `42 passed`.
- Full integrated `mix quality`: formatting, compile, Credo, and Dialyzer
  passed; `1053 passed, 1 excluded`.
- `mix compile --no-optional-deps --warnings-as-errors` passed in a clean build
  path.
- `mix docs --warnings-as-errors` passed.
- `mix run examples/04_runtime/04_09_agent_observation/semantic_boundaries.exs`
  passed with Agent, settlement, persistence, and local Topology facts.
- `git diff --check` passed.

## Completion criteria

- [x] All eight semantic families have an owner and exact event shape.
- [x] Lifecycle includes activate, stop, hibernate, and thaw.
- [x] Admission, persistence, and local Topology gaps are closed.
- [x] Every semantic event has schema version 1 and bounded safe data.
- [x] Agent Ref identity and current overlap fields have proof.
- [x] Live result and settlement remain separate.
- [x] Jido-owned observed Tasks attach and restore trace context.
- [x] Default metrics use semantic events and low-cardinality tags.
- [x] The semantic logger supports four safe modes.
- [x] OpenTelemetry API mapping is optional and infrastructure stays with the host.
- [x] Legacy `Jido.Observe`, Agent Server telemetry, and legacy metrics are removed.
- [x] Public guides, examples, and module text use the selected contract.
