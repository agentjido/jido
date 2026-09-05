> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# OBS-01: lifecycle and terminal observation

Date: **2026-09-04**. Status: **Implemented after core contract agreement**.

The core now publishes lifecycle, Turn, commit, and Directive telemetry. One
`turn.settled` event reports the final Outcome after post-commit work. The
Agent state and command contracts remain unchanged.

## Example

The [Agent](../../lib/examples/04_runtime/04_09_agent_observation/turn_observation.ex)
uses the Spark DSL, ordinary Actions, and a stateless output Plugin. The
[external collector](../../lib/examples/04_runtime/04_09_agent_observation/event_probe.ex)
listens to SDK events. It does not derive events from command replies or read
the Agent debug buffer.

```shell
mix run lib/examples/04_runtime/04_09_agent_observation/demo.exs
mix test test/jido/observe/agent_lifecycle_test.exs --seed 0
```

The runnable example reports a successful commit at revision 1, then a failed
Directive after a successful commit at revision 2. Both command calls return
success. Their terminal events explain the different final results.

## Core contract

New prefixes are `[:jido, :agent, :lifecycle]`, `:turn`, `:commit`, and
`:directive`. Each uses start, stop, and exception events. Normal returned
errors use stop with status metadata. Escaping faults and Directive task exits
use exception. Action and Plugin boundaries can contain callback exceptions
and return structured errors; these remain returned errors at the Turn boundary.

A successful Turn emits this order:

```text
turn.start
commit.start / stop
turn.stop
directive.start / stop
turn.settled
```

The Directive events are absent when there are no Directives. A failed
Directive emits an error stop, or an exception for a task exit, before the
terminal event. It does not undo the commit. Accepted cancellation and
pre-commit failure emit a classified Turn stop and settlement without a commit.

Lifecycle spans cover activation through Plugin readiness and stop cleanup.
An OTP restart gets a fresh activation ID. Requested stop during active work
reports an indeterminate Outcome before cleanup completes. Abrupt process or
VM loss can prevent final events. Telemetry is best effort, not a durable
recovery record.

Semantic metadata contains bounded Agent, activation, Signal, Turn, and trace
IDs, status, control stage, commit classification, and error type. It excludes
state, Signal and Directive payloads, raw errors, process handles, and caller
context. Revisions, Directive counts, and durations are measurements. Time
uses Erlang native units. Nonportable partition values are omitted.

Existing `:agent_server` spans remain for compatibility. The new safe-metadata
contract applies to the semantic events. Their emission needs no debug setting
or tracer callback. Export handlers must return quickly; a production export
queue and its overflow policy belong to OBS-03.

## Proof

The [nine core tests](../../test/jido/observe/agent_lifecycle_test.exs) all pass:

- Pure evaluation preserves the original Agent and emits no Agent runtime events.
- An external telemetry handler failure preserves the command result.
- Success, validation failure, execution failure, cancellation, and post-commit
  failure each emit one terminal event with the correct Outcome and revision.
- Startup, restart, and shutdown emit lifecycle events with distinct activation IDs.
- Held delivery proves that the Turn span ends at commit and settlement waits.
- Private errors, context, and nonportable partitions do not enter semantic metadata.
- Directive timeout reports the committed revision and failed entry count.
- Requested stop settles active work once.
- A crashed Directive task emits an exception and one failed terminal Outcome.

The five-Outcome test retains debug history only as an independent test oracle.
The example and other tests run with debug disabled. A context regression test
also confirms that Plugin admission still receives the original Signal.

## Validation

| Check | Result |
| --- | --- |
| OBS-01 core acceptance tests | 9 passed; no skips |
| Wider runtime, context, observation, telemetry, and two-node regression run | 212 passed before the final task-exit classification test |
| Basic through Multi-agent | 170 passed; no skips |
| Standalone observation example | Passed; exit 0 |
| `mix quality` | Passed; no compile warnings or Dialyzer findings |

The original probe had two passes and two failures on missing events. Those
failures are now resolved. No acceptance assertion was skipped. Validation
used Elixir 1.20.3 and OTP 29; the release baseline still needs a separate run.
Existing full-suite gaps remain in the [gap register](runtime-multi-agent-gaps.md).
The next target in the recorded order is REC-01.
