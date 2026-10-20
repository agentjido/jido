> Implemented seam alignment. This record maps the selected observation
> contract to its owners, compatibility rules, and evidence.

# Jido V3 observability alignment

## Status

- Contract refinement implemented: 2026-09-09.
- Documentation refinement implemented: 2026-09-10.
- Alignment state: `Implemented`.
- Compatibility state: breaking V3 cleanup. Legacy Agent Server telemetry and
  `Jido.Observe` are removed. Semantic telemetry is the single source.
- OpenTelemetry state: Core has an API-only optional mapping. The host owns the
  SDK, exporter, collector, network, credentials, resources, and vendor policy.
- Follow-on work: the V3 package and release gate remain.

## Selected decisions

| ID | Decision | Result |
| --- | --- | --- |
| `OBS-DEC-001` | Use the semantic families in the design. | AgentServer and persistence owners emit them. |
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
| AgentServer | Lifecycle, Turn, commit, returned Directives, effects, and settlement | `Jido.AgentServer` through `Jido.Telemetry.Semantic` |
| Persistence | Load, compare-and-swap, delete, storage reason, and revisions | `Jido.Telemetry.Persistence` and `Jido.Persistence` |
| Persistence Store | Direct Store operation spans | `Jido.Persistence.Store` through `Jido.Telemetry.Semantic` |
| Signal | Complete portable W3C trace carrier | Public `Jido.Signal.Trace`; private Jido runtime integration |
| Task owner | Explicit process-local trace attach and restore | Private Jido runtime integration at Jido-owned Task starts |
| Default consumers | Semantic metrics and bounded logger | `Jido.Telemetry` |
| Optional trace mapping | Semantic spans, safe attributes, error status, links, and W3C context | `Jido.Telemetry.OpenTelemetry` |
| Host | Reporters, OpenTelemetry SDK, sampling, exporters, collectors, credentials, dashboards, and alerts | Outside Jido Core |

## Event and result alignment

| Family | Operations or terminal facts | Status and measurement rule |
| --- | --- | --- |
| Lifecycle | AgentServer start and stop | Point event time |
| Turn result | Live commit or pre-commit failure | Public status, public stage, revisions, and Directive count |
| Commit | One successful commit | Status and revisions; the persistence span owns storage revisions |
| Returned Directives | One committed Directive list | Directive count |
| Effects | One post-commit batch | Status, stage, and Directive counts |
| Settlement | One bounded terminal result | Public status and stage, commit flag, revisions, Directive summary, and total duration |
| Persistence | `load`, `compare_and_swap`, `delete` | `ok`, `error`, `conflict`, `indeterminate`, `not_found`, or `rejected`; revisions are measurements |
| Persistence Store | Direct Store operations | Bounded operation, adapter, status, and duration |

A returned failure emits `:stop`. An escaping error, throw, or exit emits
`:exception`. A handler fault is contained. Abrupt process or VM loss can omit
a terminal event. Jido does not rebuild missing facts from debug history.

## Safe data alignment

All semantic events have `schema_version: 1`. The shared boundary accepts only:

- bounded Agent Ref, runtime, Turn, Signal, trace, topology, and node IDs;
- approved module fields, Boolean fields, statuses, stages, operations, and
  error codes;
- approved integer time, revision, count, and capacity measurements.

The boundary omits invalid UTF-8, oversized strings, nested values, complete
Agent state, Signal and Directive data, caller context, checkpoints, records,
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

`Jido.Telemetry.metrics/0` returns count and duration coverage for both normal
and exception span endings. It also covers lifecycle, commit, returned
Directives, effects, and settlement point events. Its tags use only fixed
operation, status, stage, reason, and component vocabularies.

The semantic logger reads `semantic_log_mode` from `config :jido, :telemetry`:

| Mode | Terminal facts logged |
| --- | --- |
| `:off` | None |
| `:errors` | Non-OK terminal facts and exceptions |
| `:interesting` | Error facts and operations over `semantic_slow_threshold_ms` |
| `:all` | Every terminal semantic fact |

The per-instance semantic log level takes priority over this value. `:on`
selects `:interesting`, and `:verbose` selects `:all`. This setting is separate
from the per-Agent debug event buffer. The logger filters the event again and
does no Agent call, storage call, or network call.

When the host declares `opentelemetry_api` and starts an SDK tracer, the same
semantic boundaries create OpenTelemetry spans. Without the optional API or an
SDK tracer, this path is a no-op.

## Compatibility and versioning

- Additive version-1 fields keep the event name and existing field meaning.
- A breaking change needs a new versioned contract and an overlap period.
- The pre-release V3 change removes `Jido.Observe`, old Agent Server events,
  their log handler, legacy metrics, and old observation configuration.
- `Jido.Signal.Trace` is the public W3C carrier. Jido trace integration stays private.
- Bounded debug history remains available through Agent Server and Ref APIs.

## Current Covenant evidence

The active `jido.telemetry` contract owns eight obligations. Its seven focused
test files contain 86 tests. The complete Covenant gate covers all eight
obligations.

The full mutation profile has 714 mutants: 657 killed, 16 classified
equivalent survivors, 41 invalid mutations, and no timeout. The separate real
OpenTelemetry SDK suite has four passing tests. The package documentation build
also passes with warnings treated as errors.
