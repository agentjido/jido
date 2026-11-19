---
title: Jido.Telemetry component
status: current
last-reviewed: 2026-11-19
---

# Jido.Telemetry component

This record covers event, logging, metric, and span ownership.

## Release review — 2026-11-19

All four checks are complete for [`6fdc009a`](https://github.com/agentjido/jido/commit/6fdc009a1edd6261f3e26509fa2905bb9192faa5) on `release/v3`. The findings are open under [#453](https://github.com/agentjido/jido/issues/453).

### Public surface

- `Jido.Telemetry.metrics/0` returns 13 reporter definitions. Turn stop and persistence operation stop and exception have counters and millisecond duration summaries. Seven AgentServer point events have counters. The tag vocabularies contain status, stage, operation, and persistence reason. Agent identity and trace IDs stay out of tags. [Core catalog](../../lib/jido/telemetry.ex), [catalog tests](../../test/jido/telemetry/api_test.exs).
- `Jido.Telemetry.open_telemetry?/0` reports whether configuration permits mapping and a host tracer is active. AgentServer and persistence operations map to spans. Point spans have zero duration. Returned error statuses and escaping faults have distinct records. Jido delegates SDK startup, sampling, and export to the host. [OpenTelemetry adapter](../../lib/jido/telemetry/open_telemetry.ex), [metrics and spans guide](../../guides/operations/metrics-and-open-telemetry.md).
- AgentServer and persistence emit schema version 1, bounded scalar metadata, and approved integer measurements. Turn stop and settlement report evaluation and commit. Effects have a separate result after commit. The event reference describes the separate Exec, Signal, AI, and ReqLLM field contracts. [Semantic normalizers](../../lib/jido/telemetry/semantic.ex), [event reference](../../guides/reference/telemetry-event-reference.md).
- The application attaches the core logger once to the metric event catalog. The default mode is `:off`. The other modes are `:errors`, `:interesting`, and `:all`. Instance startup and the documented internal `set_debug/2` entry point affect persistence operation logs for that instance. Turn and effects logs use the global mode. [Application startup](../../lib/jido/application.ex), [logging guide](../../guides/operations/telemetry-tracing-and-logs.md#debug-one-instance).

### API contract usage

- Traced runtime calls from the AgentServer worker and the persistence operation and Store adapters through semantic emission, logger attachment, reporter definitions, and span mapping. Verified the reporters and subscriptions in the observability examples. The application also starts the AI correlation store and attaches the AI handlers. AI subscribes to core Turn and Action events, and ReqLLM supplies model events. [AgentServer worker](../../lib/jido/agent_server/worker.ex), [Persistence Store](../../lib/jido/persistence/store.ex), [AI inventory](../../lib/jido/telemetry/ai.ex), [examples](../../examples/14_observability/README.md).
- The tests exercise exact metric names and tags, log filtering and escapes, event order, terminal races, context handling, and disabled or failing tracers. The pre-existing settlement link test supplies a link directly. The review probe used an actual Turn with an after-commit Plugin. The Turn's commit span was its child. The settlement and effects point spans used separate traces for an untraced Signal and became siblings under the incoming span for a traced Signal. [OpenTelemetry tests](../../test/jido/telemetry/open_telemetry_test.exs).

### Code quality

- Reuse `Jido.Error.type/1`, `retryable?/1`, and `code/1` for semantic errors. The full transport projection constructs unused message and detail fields. A local Store probe observed a returned exception's `message/1` callback run. Keep the classification and emitted fields. [Semantic error fields](../../lib/jido/telemetry/semantic.ex#L152), [Error classification](../../lib/jido/error.ex#L543).
- Keep field normalization and span mechanics shared for the core semantic families. Keep the feature-specific result vocabularies, event catalogs, and log policies. The core logger uses instance overrides. AI adds limit warnings and model data. A shared runtime observer would have to encode both policies. The metric and log subscriptions currently share one event selection through the metric catalog. [Core logger](../../lib/jido/telemetry.ex#L135), [AI logger](../../lib/jido/telemetry/ai.ex#L764).

### Elixir and OTP design

- Telemetry owns observation contracts, shared normalization, logging, metrics, and span mapping. The feature layers own the work and the event definitions they emit. Keep the shared namespace and the Reach layer assignments. `Jido.Trace` owns W3C values and propagation per D13. `Jido.Application` owns handler attachment and process startup. The Covenant records still contain earlier ownership and debug names. [Reach policy](../../.reach.exs), [architecture map](../architecture/module-dependency-map.md#telemetry), [D13](../../components.md#d13-trace-boundary).
- Keep the atomic terminal guard and same-process OpenTelemetry context restoration. Telemetry handlers run synchronously in the emitting process. The probes found that a struct returned by the measurement callback can raise after work and leave the span context installed. This conflicts with best-effort observation. AI correlation and individual Exec, Signal, and AI observation behavior are outside this review beyond their effect on the parent contract. [Semantic tests](../../test/jido/telemetry/semantic_test.exs), [OpenTelemetry adapter](../../lib/jido/telemetry/open_telemetry.ex).

### Findings

| Severity | Defect | Issue |
| --- | --- | --- |
| P2 | Settlement and effects point spans lack a relationship to the completed Turn. | [#481](https://github.com/agentjido/jido/issues/481) |
| P3 | Struct input can raise after the observed work and leave an active span context. | [#485](https://github.com/agentjido/jido/issues/485) |
| P3 | Store scans lose their operation field during normalization. | [#490](https://github.com/agentjido/jido/issues/490) |

| Severity | Behavior-preserving change | Issue |
| --- | --- | --- |
| P3 | Classify errors without formatting details. Preserve the status, type, retry flag, and error code. | [#492](https://github.com/agentjido/jido/issues/492) |
| P3 | Align the Covenant records with D13 and the current debug entry points. Preserve all proof and runtime behavior. | [#493](https://github.com/agentjido/jido/issues/493) |

### Checks

- 134 tests passed on Elixir 1.20.4 and OTP 29. The selection covered `test/jido/telemetry`, `test/jido/ai/observability`, and `examples/14_observability` with integration tests enabled. Format passed.
- Local probes confirmed scan field loss, the error message callback, struct result-measurement failure, and the actual Turn span relationships. The span probe used a local tracer. External export and live providers were outside the review.
- The Reach architecture check passed. The Covenant run passed 2,924 tests with 112 excluded. Passing tests cover all eight core Telemetry obligations and all five AI observability obligations.

### Implementation

- [#481](https://github.com/agentjido/jido/issues/481) uses the completed Turn span as the explicit parent for settlement and effects point spans. A live AgentServer test checks traced and untraced Signals, Turn completion, commit parenting, and zero-duration points.
- [#485](https://github.com/agentjido/jido/issues/485) treats structs as absent semantic metadata and measurements. A regression test checks the successful work result, one span end, and caller context restoration.
- [#490](https://github.com/agentjido/jido/issues/490) allows `:scan` as a semantic operation. The test checks successful and failed Store scans in both Telemetry and OpenTelemetry. The event names, measurements, and metric definitions use the existing catalog.
- [#492](https://github.com/agentjido/jido/issues/492) uses the existing type, retry, and code functions directly. Tests compare the classification and verify that semantic observation skips the exception message callback.
- [#493](https://github.com/agentjido/jido/issues/493) separates live-runtime Telemetry, the OpenTelemetry bridge, W3C values, and process and task propagation into layer-specific Covenant profiles. The instance debug entry points retain their persistence-only scope. [ADR 0013](../adr/0013-telemetry-proof-ownership.md).

All 153 focused tests passed after the runtime fixes and proof changes. The
regression tests reproduced the three defects before their fixes.

The sections below retain the earlier R5 review and its source context.

Review result: All four checks have evidence (R5). Findings remain open.
The user authorized the defect fixes noted below.

## Local defect fixes — 2026-11-10

F4 and F5 are fixed locally. The tool owner retains its restore token until
the terminal event, independently of correlation expiry. Log formatting drops
unsupported structured values and invalid UTF-8 strings.
The user requested these fixes without tests. No tests were added or run.
The review findings below describe the source before these fixes. Other
recommendations remain open.

## Contract and coverage

The review uses HEAD `85023dd` and the current local source changes. The ten
files contain 3,136 lines. Elixir support is `~> 1.18`; the checks used 1.20.4.

| Responsibility | Public surface and traced boundary | Coverage |
| --- | --- | --- |
| Core | `metrics/0`, `open_telemetry?/0`, `set_debug/1,2`, `debug_level/1`, `debug_status/1`; configuration and default event handler exports support instance startup. Debug state belongs to the instance. | Source, instance callers, debug and logging tests traced. |
| Semantic events | Internal span and event helpers restrict metadata and measurements. A terminal guard prevents duplicate span completion. Returned domain errors and escaping faults have distinct event forms. | Success, returned error, raise/throw/exit, and nested span tests traced. |
| AgentServer | Event inventory, span helpers, and point measurements describe admission, Turns, effects, and runtime state. | AgentServer call sites and event tests traced. |
| Exec | `event_names/0`, `span/3`, effect-count recording, Action/Flow metadata and result mapping. Uses `outcome`, rather than core `status`. | Runtime/node callers, tests, and fault probe traced. |
| Persistence and Signal | Persistence spans report storage operations. Signal `execute/2,3,4` adds bounded trace metadata to routing, Bus, and dispatch events. | Store and delivery call sites, success/error tests traced. |
| AI | `events/0`, `owned_events/0`, `metrics/0`, `attach/2,3`, `open_telemetry?/0`, `attach_open_telemetry/0,1`, default handlers, and runtime instrumentation helpers. ReqLLM owns model request events. | Agent, reasoning, tool, and model bridge tests traced. |
| OpenTelemetry | Core and AI adapters map events to host-managed spans. Neither starts an SDK or exporter. Normal work restores context tokens. AI expiry has a cleanup defect (F4). AI also correlates asynchronous operations. | Optional-dependency and context tests traced; no live collector used. |
| CorrelationStore | One supervised GenServer owns a public ETS table and expiry timer. Direct reads/writes tolerate a missing table. Sweeps remove the matching generation and end expired spans. | Startup, cleanup, expiry, and bridge tests traced. |

These rows close source coverage. A test result does not prove every possible
reporter or collector. Trace values and propagation belong to `Jido.Trace`,
as settled in D13. Telemetry must not decide retry, recovery, or state policy.

## Usage and design

Subsystem modules are used by their corresponding runtime owners. AI observes
AgentServer and Exec events to relate one request to tools and model calls.
This is a real boundary: an asynchronous AI span cannot be replaced by the
core synchronous span wrapper alone. Keep the host's SDK and export choices.

The root metadata allowlist is not a namespace-wide promise. Exec, Signal, and
AI have their own event shapes. Document these separately before combining
the event helpers. Do not remove subsystem names solely to reduce file count.

Core and AI repeat log-mode selection, slow thresholds, value escaping, and
truncation. Their event selection differs. A small common value formatter is
a possible cut; a new generic observer framework is not justified.

## Findings

- **F1 — Safe refinement, P3, high confidence.** In
  `lib/jido/telemetry/exec.ex:37`, an Action span sets a process-dictionary
  effect counter. Only normal completion deletes it. A caught throw, raise,
  or exit leaves that counter in a surviving caller process. A temporary
  probe threw inside `span(:action, %{}, fun)`, caught the throw, and found
  `Process.get({Jido.Telemetry.Exec, :effect_count}) == 0`. Restore the prior
  value in an `after` block so nested calls also keep their scope. This is a
  local cleanup change; verify normal, nested, and fault paths before adoption.
  No external execution failure was proved; public execution normally uses tasks.
- **F2 — Safe refinement, P2, high confidence.** AI repeats the core string
  formatter in `lib/jido/telemetry/ai.ex:920`. A captured log retains U+2028;
  the core formatter escapes Unicode line separators. Use the same bounded
  scalar formatting rule if both log surfaces require one visual line. The
  observable log text will change. This probe proves different output, not
  a leak of prompts or credentials.
- **F3 — Investigation, P3.** Correlation expiry bounds retention time, not
  maximum item count. Measure active cardinality before adding a capacity
  policy. No memory failure was reproduced. Keep generation-safe deletion.
- **F4 — Defect, P2, high confidence.** In
  `lib/jido/telemetry/ai/open_telemetry.ex:288`, expiry restores context only
  when the expiry caller owns the span. The normal sweep runs in the store
  process and removes the restore token. A later tool stop finds no record.
  A probe started a tool span, pruned it from a separate Task, then emitted
  stop from the owner. The owner still had the expired tool context. Later
  work can use the wrong parent. Keep owner context restoration separate from
  the expiring record; preserve single span completion. This needs no public
  API change. Test the separate-process sweep, rather than only owner-local
  prune, and verify nested span restoration.
- **F5 — Defect, P2, high confidence.** At
  `lib/jido/telemetry/ai.ex:918`, unsupported log values use `inspect/2`.
  `jido_ai.observability.I5` requires bounded scalar metadata. A captured
  agent-stop log with `error_type: %{api_key: "AI_SECRET_MARKER"}` printed
  the marker. Drop unsupported metadata and measurement values before
  formatting; remove the general inspection fallback. Valid scalar output
  can stay the same. Verify the public event handler and assert that markers
  under nested values are absent. The probe used the public event boundary;
  it does not prove an ordinary model response reaches this exact shape.
- **Design decision.** Subsystem instrumentation can stay near its runtime
  owner while shared formatting and span mechanics stay central. Mike must
  settle component placement; current namespace shape does not decide it.

## Checks and proof gaps

The first focused R5 command passed 184 tests, including Telemetry and AI
observability. Fault, expiry and log probes used a temporary script outside the repo.
A second reviewer checked Bus and the Telemetry ownership paths; the primary
reviewer reproduced the retained defects. Persistence and Signal core, Router,
and Dispatch were self-checked.
The broad CI limit is recorded in [R5](../../components.md).

`jido.telemetry` still includes Trace proof ownership that conflicts with D13.
AI has a separate legacy `jido_ai.observability` proof surface. Exec and Signal
instrumentation also have tests under their observed subsystems. Real exporter
delivery, load/cardinality bounds, and external model calls remain unverified.

## Sources

- [Core](../../lib/jido/telemetry.ex)
- [Semantic helpers](../../lib/jido/telemetry/semantic.ex)
- [Exec instrumentation](../../lib/jido/telemetry/exec.ex)
- [AI](../../lib/jido/telemetry/ai.ex)
- [Correlation store](../../lib/jido/telemetry/ai/correlation_store.ex)
- [Core tests](../../test/jido/telemetry)
- [AI tests](../../test/jido/ai/observability)
- [Telemetry obligations](../../test/contracts/jido/telemetry.obligations.md)
