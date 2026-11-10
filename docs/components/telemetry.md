---
title: Jido.Telemetry component
status: current
last-reviewed: 2026-11-10
---

# Jido.Telemetry component

Purpose: Record event, logging, metric, and span ownership.
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
