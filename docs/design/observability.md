> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Observability

[Design overview](README.md) | Previous: [Runtime topology](runtime-topology.md) | Next: [Errors](errors.md)

- Status: Proposal for v3 spike review
- Depends on: Signal trace context, the Agent Server, Agent Commit, Turn
  Outcome, persistence, and Directives.
- Defines: semantic telemetry events, correlation, safe metadata, metrics, and
  logging.

## Implemented OBS-01 subset

The user approved the OBS-01 instrumentation scope on 2026-09-04. Core now
emits lifecycle (`:activate`, `:stop`), Turn, commit, and Directive spans, plus
`turn.settled`. These semantic events use bounded metadata and native time
units. Existing `:agent_server` spans remain for compatibility. See the
[nine-test implementation report](../examples/obs-01-results.md).

The sections below retain the wider target design. The full persistence event
contract, admission events, consumer configuration, trace-carrier migration,
and removal of the old debug/tracer APIs remain pending work. Approval of the
OBS-01 subset does not approve this entire document.

## Goal

Observability describes Agent execution. It does not participate in execution.

- `Jido.Agent.cmd/3` emits no telemetry.
- Live execution emits standard `:telemetry` events.
- Core has no tracer callback or observer failure policy.
- An observer cannot change a candidate, Commit, Result, or Directive.
- Telemetry contains bounded identity and classification data. It contains no
  Agent state, Plugin state, Signal payload, or Directive payload.
- Agent Server state contains no debug timeline or observation buffer.

## Stable semantic events

Core makes only semantic boundaries stable:

| Event prefix | Meaning |
| --- | --- |
| `[:jido, :agent, :lifecycle]` | Create, activate, hibernate, thaw, stop, or delete an Agent. |
| `[:jido, :agent, :turn]` | Process one admitted Signal through the live Result boundary. |
| `[:jido, :agent, :commit]` | Attempt to make one candidate Agent live. |
| `[:jido, :persistence, :operation]` | Load or compare-and-swap one Agent Record. |
| `[:jido, :agent, :directive]` | Dispatch one post-commit Directive. |

Each prefix emits standard span events:

```elixir
prefix ++ [:start]
prefix ++ [:stop]
prefix ++ [:exception]
```

Core also emits two point events:

```elixir
[:jido, :agent, :turn, :settled]
[:jido, :agent, :admission, :rejected]
```

`turn.settled` carries the terminal bounded Turn Outcome. Admission rejection
reports a Signal that did not start evaluation.

Route selection, Plugin preparation, executable calls, Plugin contribution,
and candidate validation are implementation stages inside evaluation. Core
does not publish stable events for them. Action and Flow packages can publish
live execution events in their own namespaces without changing the Jido core
event contract. Pure Plugin callbacks emit no telemetry.

## Runtime event order

A successful persistent Turn has this observable order:

```text
turn.start
  package-owned executable events, when enabled
  commit.start
    persistence.operation.start / stop
  commit.stop
turn.stop
directive.start / stop
turn.settled
```

The Turn span starts after admission. It stops when the Commit and live Result
exist, or when evaluation produces a pre-commit error. Directive work is not
part of live Result latency. `turn.settled` occurs after the current Directive batch
completes or a Directive fails. It does not mean all background business work
is complete.

A recovery worker can retry explicit pending work after activation. These
attempts belong to the capability, not to replay of the original Turn. A
completion Signal starts a new Turn with its own commit and settlement. The
capability owns any work-attempt telemetry beyond the core runtime events.

Direct `Jido.Agent.cmd/3` tells executable packages to disable live runtime
observation. A live Agent execution can enable package events and pass private
correlation options. These options do not enter Action input, Plugin input, or
Agent state.

## Stop and exception meaning

A `:stop` event means that work returned normally. Its status can be success or
a returned error. An `:exception` event means that work raised, threw, or
exited.

Returned validation errors, conflicts, timeouts, cancellation, and
indeterminate writes use `:stop` with classification metadata. Broken internal
invariants use `:exception` and let OTP apply the restart source.

Core telemetry uses only the three Turn control stages:

```elixir
%{
  status: :ok | :error | :cancelled | :timed_out | :conflict | :indeterminate,
  stage: :evaluate | :commit | :directive,
  committed?: boolean(),
  write_authority: :not_applicable | :retained | :lost
}
```

An accepted cancellation and `turn_timeout` stop at `:evaluate` with no
commit. A persistence timeout stops at `:commit` as indeterminate and loses
write authority. Every persistence write error reports lost write authority.
A Directive timeout stops at `:directive`, has `committed?: true`, and leaves
the entry pending.

A caller wait timeout is not a Server work event. A postponed request that
reaches its admission deadline emits `admission.rejected`.

## Measurements

Span starts include monotonic time. Span stops and exceptions include duration
in native time units. Event-specific numeric measurements can include:

- State version before and after commit.
- Directive index and count.
- Postponed Signal count and limit.
- Runtime readiness duration.
- Settlement duration.

State versions and counts are measurements, not metadata tags.

## Common metadata

Common metadata is a bounded Map:

```elixir
%{
  jido_namespace: "my-app/primary",
  agent_module: MyApp.OrderAgent,
  agent_id: "order-123",
  partition: nil,
  turn_id: "019...",
  source_signal_id: "019...",
  signal_id: "019...",
  signal_type: "order.create",
  trace_id: "...",
  span_id: "...",
  parent_span_id: "...",
  causation_id: "...",
  cause_turn_id: "...",
  child_activation_id: "...",
  sampled?: true
}
```

Fields that do not apply are absent. Event metadata can add Plugin ID, Plugin
module, stable Directive ID, Directive module, persistence operation,
lifecycle operation, restart mode, and a bounded public error projection.

Metadata never contains:

- Agent domain state or Plugin state.
- Signal data or source objects.
- Directive payloads.
- Checkpoints, Commits, or persistence Records.
- Runtime Init or Context values.
- Stacktraces or arbitrary exception terms.
- PIDs, functions, ports, references, or arbitrary application metadata.

Telemetry emission uses safe internal normalization. Invalid metadata cannot
change the Agent result.

## Trace and causation

`Jido.Tracing.Trace` reads and writes Signal trace context. The Agent Server
creates a root trace when a Signal has none. Outbound Signal Directives create
a child span; the receiving Turn uses that Signal trace.

A recovery capability must explicitly store the trace and causation fields it
needs across restart. Ordinary Directives are not automatically persisted.
Process-dictionary context can support Logger, but it is not durable state.
REC-01 proves delivery identity, not cross-restart trace continuity.

Trace links and Signal causation are different. A Directive-created Signal
gets a child trace and sets its causation ID to the source Signal ID. Sampling
does not remove causation.

`SpawnAgent` captures a private creation cause from the spawning Turn: trace ID,
span ID, Signal ID, and Turn ID. Immediate and delayed `ChildStarted` Signals
use that cause. Retrying an unresolved remote start retains the original cause
and creation request identity. Each retry Turn still has its own Turn identity.

Child activation and stop events use fresh spans under the creation cause.
An OTP restart receives a new activation ID but retains its original creation
cause. A child-start notification includes `child_activation_id` to identify
that activation. Explicit replacement captures a new cause. Later business
commands derive their traces from their own incoming Signals.

Signal context carries `jidocausationid`, `jidocauseturnid`, and
`jidochildactivation`; semantic telemetry exposes them as `causation_id`,
`cause_turn_id`, and `child_activation_id`. `source_signal_id` retains its
existing meaning: the Signal submitted to the observed Turn.

The cause travels in private startup options and the parent relationship. The
runtime relationship binding retains it for local process restoration during
the same Jido instance lifetime. It is not part of a durable Agent checkpoint.
A start with no saved cause keeps the existing root behavior. This contract
does not claim cause recovery after Jido instance or VM loss.

## Metrics

`Jido.Telemetry.metrics/0` returns standard metric definitions. Core does not
start or select a reporter.

The initial metrics are:

- Turn count, Result latency, and error count.
- Commit count, duration, and status count.
- Persistence operation count, duration, write-error count, conflict count,
  indeterminate count, and lost-write-authority count.
- Directive count, duration, and error count.
- Admission rejection count.
- Agent lifecycle count and duration.
- Turn settlement duration.

Default metric tags can include Jido namespace, Agent module, Signal type,
operation, status, control stage, Plugin module, and Directive module. They do
not include Agent ID, Signal ID, Turn ID, trace ID, Directive ID, operation ID,
or storage version.

## Logging

Logging is an optional telemetry consumer. `Jido.Telemetry.Logger` supports:

```elixir
false | :errors | :interesting | :all
```

`:interesting` includes returned errors, rejected admission, slow Turns,
persistence write errors, lost write authority, and Turns that produce
Directives. Logging follows the same metadata exclusions as telemetry.

## Instance configuration

The Jido instance configures built-in consumers only:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    observability: [
      log: :errors,
      slow_turn_ms: 1_000,
      slow_directive_ms: 1_000
    ]
end
```

Live telemetry emission is independent of this setting. Core has no debug
buffer, tracer module option, exporter credentials, payload logging, or option
that disables redaction.

## Handler safety

Telemetry handlers run in the emitting process. A handler must return quickly
and must not call the observed Agent, access storage, or perform network I/O.
Exporters must move slow work to another process.

The optional core logger uses bounded values and preserves the Agent result if
formatting fails. Core does not wait for log, metric, or trace export.

## Public modules

- `Jido.Telemetry` defines and emits stable semantic events.
- `Jido.Telemetry.Metrics` defines standard metrics.
- `Jido.Telemetry.Logger` is the optional built-in log handler.
- `Jido.Signal.Trace` carries W3C trace context.

Core does not provide `Jido.Debug`, a per-Agent timeline, or stable events for
internal evaluation stages. An application can build a timeline as an external
telemetry consumer.

## Required tests

- Direct `Jido.Agent.cmd/3` emits no telemetry.
- Live execution emits semantic events in the defined order.
- Internal evaluation stages do not add stable core event names.
- The Turn span stops before Directive dispatch.
- Returned errors emit `:stop`; raises, exits, and throws emit `:exception`.
- Agent state, Plugin state, and payloads do not enter metadata.
- Trace IDs continue from incoming Signals. A durable capability must define
  and test its own saved trace carrier.
- A Directive-created Signal carries child trace and causation data.
- A telemetry handler failure cannot change an Agent Result.
- Agent Server state contains no observation buffer.
