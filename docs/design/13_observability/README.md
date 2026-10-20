> Implemented for the V3 observability contract.

# 13 - Observability

## Briefing

Jido now uses one semantic event catalog for AgentServer lifecycle, Turn
result, commit, Directive work, effects, Turn settlement, and persistence.

Every semantic event has `schema_version: 1`. The event boundary keeps only
approved scalar metadata. It omits state, payloads, raw errors, records,
credentials, process handles, and arbitrary application metadata. Counts,
durations, and revisions stay in measurements.

Observation has no execution or persistence authority. A handler failure does
not change the command result, durable result, or public Turn Outcome.

## Event catalog

| Family | Event | Meaning |
| --- | --- | --- |
| AgentServer lifecycle | `[:jido, :agent_server, :lifecycle, :start | :stop]` | One live activation boundary |
| AgentServer Turn | `[:jido, :agent_server, :turn, event]` | Turn start to live result or pre-commit failure |
| AgentServer commit | `[:jido, :agent_server, :commit]` | One successful commit fact |
| Returned Directives | `[:jido, :agent_server, :directives, :returned]` | Count returned at commit |
| AgentServer effects | `[:jido, :agent_server, :effects, :start | :stop]` | One post-commit effects batch |
| Turn settlement | `[:jido, :agent_server, :turn, :settled]` | One bounded terminal result |
| Persistence | `[:jido, :persistence, :operation, event]` | Load, compare-and-swap, or delete |
| Persistence Store | `[:jido, :persistence, :store, event]` | One direct Store operation |

For a span, `event` is `:start`, `:stop`, or `:exception`. A returned failure
uses `:stop`. A fault that escapes the observed boundary uses `:exception`.

The successful Turn span ends when the commit becomes live. Directive work can
settle later. The separate `turn.settled` fact keeps this difference visible.

## Identity and correlation

When an instance has a stable namespace, Agent events project the exact Agent
Ref fields as `agent_namespace`, `agent_partition`, and `agent_id`. Duplicate
`jido_instance` and `partition` fields are not public metadata.

Activation, Turn, source Signal, effective Signal, trace parent, and Signal
causation IDs stay separate. Signals keep the complete portable W3C carrier.
`Jido.Signal.Trace` is the public W3C carrier. Jido-owned Tasks explicitly
attach and restore their private process-local trace context.

## Consumers

`Jido.Telemetry.metrics/0` returns low-cardinality metrics from semantic events.
It does not use Agent, Signal, trace, topology, or error IDs as default tags.

The semantic logger supports `:off`, `:errors`, `:interesting`, and `:all` with
`semantic_log_mode`. It filters metadata and measurements again before it
writes a log entry.

Jido has an API-only OpenTelemetry mapping through the optional
`opentelemetry_api` dependency. It uses the same semantic boundaries and safe
fields. The host owns the SDK, sampling, exporters, collector, credentials,
resources, and vendor configuration.

## Compatibility

- Keep semantic version-1 names and field meanings for additive changes.
- Use a new versioned contract for a breaking schema change.
- Remove old Agent Server events and `Jido.Observe` before the V3 release.
- Keep W3C trace transfer and bounded debug history.
- Keep telemetry best-effort. Do not use it as a durable audit record.

## Evidence

- AgentServer tests prove lifecycle, live result, commit, returned Directive,
  effects, settlement, privacy, and failure isolation facts.
- Persistence tests prove load, compare-and-swap, conflict, delete, status,
  revision, and privacy facts.
- Telemetry tests prove schema normalization, stable error codes, semantic
  metrics, and four log modes.
- OpenTelemetry tests prove the optional API mapping, safe attributes, links,
  disabled behavior, portable Signal context, and explicit Task restoration.
- The semantic boundary demonstration runs all main families together.

## Documents

- [Selected design](design.md)
- [Implemented alignment and evidence](alignment.md)
