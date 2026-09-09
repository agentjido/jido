> Implemented seam review entry point.

# 13 - Observability

## Briefing

Jido now uses one semantic event catalog for Agent lifecycle, Turn result,
commit, Directive work, Turn settlement, admission rejection, persistence, and
the static local Topology Controller.

Every semantic event has `schema_version: 1`. The event boundary keeps only
approved scalar metadata. It omits state, payloads, raw errors, records,
credentials, process handles, and arbitrary application metadata. Counts,
durations, and revisions stay in measurements.

Observation has no execution or persistence authority. A handler failure does
not change the command result, durable result, or public Turn Outcome.

## Event catalog

| Family | Event | Meaning |
| --- | --- | --- |
| Agent lifecycle | `[:jido, :agent, :lifecycle, event]` | Activation, stop, hibernate, or thaw |
| Agent Turn result | `[:jido, :agent, :turn, event]` | Admission to live result or pre-commit failure |
| Agent commit | `[:jido, :agent, :commit, event]` | One commit attempt, including required persistence |
| Agent Directive | `[:jido, :agent, :directive, event]` | One post-commit Directive attempt |
| Turn settlement | `[:jido, :agent, :turn, :settled]` | One terminal public Outcome |
| Admission rejection | `[:jido, :agent, :admission, :rejected]` | Deadline or overload rejection before a Turn |
| Persistence | `[:jido, :persistence, :operation, event]` | Load, compare-and-swap, or delete |
| Local Topology | `[:jido, :topology, :operation, event]` | Activation, repair, or cleanup |

For a span, `event` is `:start`, `:stop`, or `:exception`. A returned failure
uses `:stop`. A fault that escapes the observed boundary uses `:exception`.

The successful Turn span ends when the commit becomes live. Directive work can
settle later. The separate `turn.settled` fact keeps this difference visible.

## Identity and correlation

When an instance has a stable namespace, Agent events project the exact Agent
Ref fields as `agent_namespace`, `agent_partition`, and `agent_id`. The current
`jido_instance` and `partition` fields stay during the compatibility interval.

Activation, Turn, source Signal, effective Signal, trace parent, and Signal
causation IDs stay separate. Signals keep the complete portable W3C carrier.
Jido-owned Tasks explicitly attach and restore their process-local trace
context.

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

- Agent lifecycle tests prove Ref projection, hibernate, thaw, live result,
  settlement, rejection, privacy, and failure isolation.
- Persistence tests prove load, compare-and-swap, conflict, delete, status,
  revision, and privacy facts.
- Topology tests prove activation, repair, cleanup, status, counts, and privacy.
- Telemetry tests prove schema normalization, stable error codes, semantic
  metrics, and four log modes.
- OpenTelemetry tests prove the optional API mapping, safe attributes, links,
  disabled behavior, portable Signal context, and explicit Task restoration.
- The semantic boundary demonstration runs all main families together.

## Documents

- [Selected design](design.md)
- [Implemented alignment and evidence](alignment.md)
