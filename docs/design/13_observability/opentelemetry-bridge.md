# Core OpenTelemetry bridge

> Supporting observability design. This document is pending approval.

Design source: [Observability](observability.md).

## Goal

Give a production Jido system one clear observation path:

```text
Jido semantic events -> metrics, logs, and traces -> operator backend
```

Move the Jido-to-OpenTelemetry translation into Jido core. Make the
OpenTelemetry API optional. Let the host application own the SDK, exporter,
Collector, and backend. Retire `jido_otel` after users can move to core.

This work reduces package count and removes the generic tracer callback
system. It keeps the semantic events and trace detail that a production system
needs.

## Decision summary

1. Keep `:telemetry` as the stable and vendor-neutral event contract.
2. Put the mapping from Jido semantic events to OpenTelemetry spans in core.
3. Add only `opentelemetry_api` to Jido, with `optional: true`.
4. Do not add the OpenTelemetry SDK or an exporter as a Jido dependency.
5. Do not use an Agent Plugin for observation.
6. Add one public module, `Jido.OpenTelemetry`. Keep its handler, attribute
   mapping, and process-context helpers private.
7. Start the bridge when the optional API is present. Let the host disable it
   with `config :jido, :opentelemetry, enabled: false`.
8. Map traces in the first release. Keep metrics in `Jido.Telemetry.metrics/0`
   and logs in Logger.
9. Use `Jido.Signal.Trace` as the W3C carrier across Signal boundaries.
10. Explicitly copy OpenTelemetry context across each Task boundary that Jido
    owns. Do not depend on implicit process inheritance.
11. Remove duplicate `:agent_server` spans after the semantic path has equal
    or better test coverage.
12. Deprecate and then remove `Jido.Observe.Tracer`, `SpanCtx`, NoopTracer,
    tracer failure policy, and scoped tracer callbacks.
13. Keep AI semantics in `jido_ai`. Core does not know about models, tokens,
    prompts, tools, retrieval, or cost.
14. Send data to Langfuse or another service through standard OTLP. Do not add
    a Langfuse dependency or credentials to core.

## Current state

Core has two observation paths:

- Stable semantic Agent events under `[:jido, :agent, ...]`.
- Legacy Signal and Directive spans under `[:jido, :agent_server, ...]`.

`jido_otel` maps the legacy `Jido.Observe.Tracer` callbacks. It does not map
the complete semantic event set. It also has its own configuration, release,
and version constraint. Moving those files without changing the contract would
keep the duplicate system.

The implementation must use the semantic events as its only source. It must
not copy the old tracer adapter into core.

## Target package boundary

```text
Jido core
  -> semantic :telemetry events
  -> optional Jido.OpenTelemetry trace bridge

Host application
  -> OpenTelemetry SDK, sampler, processors, and resource data
  -> OTLP exporter and Collector
  -> operations or Agent observation service
```

The host controls sampling, batching, export retry, shutdown, service data,
and credentials. Jido performs no network I/O in a Telemetry handler.

The target dependency choices are:

| Use case | Host dependencies |
| --- | --- |
| Jido events and custom handlers only | `jido` |
| Jido metrics | `jido` plus the selected Telemetry reporter |
| OpenTelemetry traces without export | `jido` plus `opentelemetry` |
| OTLP export | `jido`, `opentelemetry`, and `opentelemetry_exporter` |
| Langfuse | The OTLP set, with a Collector or Langfuse OTLP endpoint |

There is no `jido_otel` dependency in the target system.

## Dependency and compile design

Add this dependency to Jido:

```elixir
{:opentelemetry_api, "~> 1.5", optional: true}
```

Confirm the exact supported range when implementation starts. Do not add
`:opentelemetry_api` or `:opentelemetry` to Jido `extra_applications`.

Define `Jido.OpenTelemetry` in all builds. It delegates to a private
implementation only when the API modules are available. Keep OTel structs,
macros, and typespecs inside the optional implementation so compilation
without the dependency has no warnings.

Use a consumer fixture that depends on Jido but does not add OpenTelemetry.
This fixture is the required proof for the optional dependency. Jido's own
development environment fetches optional dependencies, so a normal core
compile is not sufficient proof.

## Public surface

Keep the API small:

```elixir
Jido.OpenTelemetry.available?()
Jido.OpenTelemetry.enabled?()
```

Normal applications do not call setup code. Jido attaches the handler during
Jido application startup. Do not expose span handles, task wrappers, process
dictionary keys, adapter callbacks, or attribute sanitizers.

## Trace mapping

The bridge attaches only to these stable boundaries:

- Agent lifecycle.
- Turn start, Result, fault, and settlement.
- Commit.
- Persistence operation.
- Directive.
- Admission rejection.

It ignores the legacy `[:jido, :agent_server, ...]` events.

The handler starts an OpenTelemetry Turn span on `turn.start`. It records the
live Result on `turn.stop` or `turn.exception`, but it keeps the span open. It
ends the span on `turn.settled`. This lets commit and Directive spans have one
useful parent. The Telemetry Result-duration metric stays separate from the
longer OpenTelemetry Turn span duration.

Use the standard `telemetry_span_context` reference to match start and terminal
events. Keep open OTel contexts in the emitting process dictionary. Remove
them when work ends. Do not add an ETS table, a handler process, or exporter
state to Agent Server.

Normal Agent termination must emit terminal events and clear its context.
Abrupt process or VM loss can omit a final event. This is also a limit of the
base Telemetry contract. Do not add a trace-repair service to core.

Use a stable `jido.*` attribute namespace. High-cardinality IDs can be span
attributes, but they cannot be metric tags. Returned errors set status and
bounded error attributes. Only a raise, throw, or exit creates an exception
event. State, payloads, raw error terms, and arbitrary context cannot become
span attributes.

## Process and Signal propagation

OpenTelemetry context is process-local. A Task does not inherit it. Add one
private wrapper that captures the current context before process start,
attaches it inside the child, and detaches it in `after`.

Apply the wrapper to each process boundary that Jido owns:

- Plugin admission Tasks.
- Asynchronous Action or Flow execution.
- Directive Tasks.
- Plugin readiness work.
- Error-policy work during the compatibility period.
- Any persistence Task added later.

Audit `Jido.Exec` separately. It is in `jido_action` and owns parallel Flow
Tasks. Add the same optional API pattern in that package or pass an explicit
private context through its execution options. Do not add a dependency from
`jido_action` back to Jido core.

For Signals:

1. Extract `traceparent` and `tracestate` before a Turn starts.
2. Let the SDK create the Turn span and apply its sampling decision.
3. Inject the current context into each outbound Signal before dispatch.
4. Keep Jido causation ID and cause Turn ID separate from trace parentage.
5. Preserve the W3C carrier through remote and delayed delivery.
6. Require a durable capability to save a carrier when it needs trace
   continuity after restart.

Do not use a fixed `00` sampling flag when an SDK creates the root. Do not use
a process dictionary as the wire or durable carrier.

## Work sequence

### Phase 1: complete the semantic contract

1. List every stable event, measurement, and metadata field in
   `Jido.Telemetry`.
2. Add `traceparent`, bounded `tracestate`, and the reserved
   `telemetry_span_context` field where a span needs them.
3. Add the missing admission and persistence events.
4. Add the production metric set from the observability design.
5. Add tests that reject state, payload, PID, function, port, reference, and
   arbitrary application metadata. Permit only the reserved span reference.

Exit condition: logs, metrics, and traces can use one event contract without
`Jido.Observe`.

### Phase 2: add the optional core bridge

1. Add the optional API dependency and compile boundary.
2. Add `Jido.OpenTelemetry` and its private handler.
3. Map Turn, commit, persistence, Directive, lifecycle, and admission events.
4. Add bounded attributes, status mapping, exception recording, and cleanup.
5. Add the global opt-out. Do not add per-Agent trace configuration.
6. Add the consumer fixture with no OTel dependency.

Exit condition: one core Turn produces one correct OTel Turn span, and an
installation without OTel has the same Jido behavior.

### Phase 3: prove context across OTP boundaries

1. Wrap every Jido-owned Task start with explicit capture and attach.
2. Extract an incoming W3C Signal parent.
3. Inject the current context into outbound Signals.
4. Test parentage across Agent Server, execution Task, Directive Task, child
   Agent, and a Signal encode and decode boundary.
5. Test concurrent Agents for context leaks and crossed traces.

Exit condition: an end-to-end trace has no orphan Jido spans after success,
returned error, timeout, cancellation, or normal process shutdown.

### Phase 4: remove the duplicate core system

1. Stop the legacy `[:jido, :agent_server, ...]` Signal and Directive spans.
2. Keep `Jido.Observe.with_span/3` as a deprecated Telemetry wrapper for one
   migration release.
3. Remove the tracer callback, scoped callback, NoopTracer, SpanCtx, tracer
   selection, and strict failure mode.
4. Remove the old debug timeline from Agent Server state. Keep status and OTP
   `format_status/1` inspection.
5. Remove old configuration keys and update migration tables in the guides.

Exit condition: core has one event path, one trace bridge, and no observer code
that can run the observed function.

### Phase 5: align ecosystem packages

1. Change `jido_ai` to emit stable generation, tool, retrieval, guardrail,
   token, and cost events.
2. Give `jido_ai` its own optional OpenTelemetry mapping for GenAI attributes.
3. Confirm that `req_llm` spans inherit the Jido Turn or Jido AI run context.
4. Confirm that Jido Action Flow Tasks keep context across parallel work.
5. Add one full trace fixture from an HTTP or Req parent through Jido, an LLM
   call, a tool call, and a child Agent.

Exit condition: a production trace has OTP runtime spans and AI-specific spans
without duplicate model or tool spans.

### Phase 6: document operations and retire `jido_otel`

1. Add a guide for SDK setup, OTLP export, Collector routing, sampling, and
   shutdown.
2. Add a Langfuse recipe that uses OTLP and keeps credentials in the host.
3. Add a migration guide from `Jido.Otel.Tracer` configuration.
4. Update `jido_otel` to point users to the core release that contains
   `Jido.OpenTelemetry`.
5. Archive the package after its supported users can move.

Exit condition: a user can remove one dependency and one tracer setting, then
keep equivalent or better traces.

## Test matrix

Run these as separate CI jobs where dependency resolution differs:

| Matrix case | Required result |
| --- | --- |
| Jido with no OTel packages | Compile with warnings as errors; all core behavior works. |
| OTel API present, bridge disabled | No Jido spans; semantic events remain. |
| OTel API present, SDK absent | No crash; API behavior is a no-op. |
| OTel SDK with in-memory exporter | Exact span names, parents, status, attributes, and terminal count. |
| OTLP exporter integration | A bounded batch reaches a local Collector; Agent work does not wait for export. |
| Concurrent Agent load | No cross-trace parentage, context leak, or unbounded bridge state. |

Failure tests must include returned errors, raises, throws, exits, timeout,
cancellation, commit conflict, uncertain persistence write, Directive failure,
normal Agent shutdown, and bridge-handler failure.

Privacy tests must prove that Agent state, Plugin state, Signal data, Directive
data, secrets, raw errors, and arbitrary context do not enter span attributes.
Content capture stays an explicit `jido_ai` decision.

## Migration from `jido_otel`

Old host setup:

```elixir
{:jido_otel, "~> 0.1"}

config :jido, :observability,
  tracer: Jido.Otel.Tracer
```

Target host setup:

```elixir
{:jido, "~> 3.0"},
{:opentelemetry, "~> 1.7"},
{:opentelemetry_exporter, "~> 1.0"}
```

Remove the `tracer:` setting. Keep SDK and exporter configuration in the host.
Do not define `Jido.Otel` in core. This prevents a duplicate module while the
old package is installed. Use `Jido.OpenTelemetry` for the new public name.

## Langfuse path

Langfuse accepts OTLP traces. The first integration is a documented export
recipe, not a Jido package:

```text
Jido and Jido AI -> OTel SDK -> OTLP Collector -> Langfuse
```

Core sends stable Agent and Turn fields. `jido_ai` sends model, generation,
tool, token, and cost fields. The host adds session, user, release,
environment, and tenant attributes according to its data policy.

A future Langfuse-specific package is justified only if users need its
non-OTLP APIs, such as scores, prompt management, data sets, or evaluation
workflows. It is not required for traces.

## Definition of done

- Jido works with no OpenTelemetry package installed.
- A host can enable production traces without `jido_otel` or a tracer setting.
- One Signal produces one Jido Turn span with correct parentage through all
  Jido-owned Tasks and outbound Signals.
- Metrics and logs still come from the same semantic events.
- No legacy Agent Server span duplicates a semantic span.
- Observation failures cannot change an Agent Result.
- Agent Server state has no debug history or exporter state.
- The Langfuse OTLP recipe works without vendor code in core.
- Core and ecosystem guides use one vocabulary for Agent, activation, Turn,
  run, and session.

## References

- [OpenTelemetry library instrumentation](https://opentelemetry.io/docs/concepts/instrumentation/libraries/)
- [OpenTelemetry Erlang and Elixir instrumentation](https://opentelemetry.io/docs/languages/erlang/instrumentation/)
- [OpenTelemetry context across Erlang processes](https://opentelemetry.io/docs/languages/erlang/instrumentation/#spans-in-separate-processes)
- [Langfuse OpenTelemetry integration](https://langfuse.com/integrations/native/opentelemetry)
