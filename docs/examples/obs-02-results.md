> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# OBS-02: causal trace across Agents

Date: **2026-09-04**. Status: **Implemented after approval of the creation-cause contract**.

The original child-start failure is fixed. The probe now covers local and remote
work, results, startup, delayed startup, retry, failure, and OTP restart. The
12 tests use real Agent Servers and SDK telemetry: eight local tests and four
two-node tests. No test is skipped.

## Example

The [Agent example](../../lib/examples/04_runtime/04_10_causal_trace/causal_trace.ex)
sends work to two children and collects their results. It uses `SpawnAgent`,
`EmitToChild`, and `EmitToParent`. It adds no trace fields or application telemetry.
The external [EventProbe](../../lib/examples/04_runtime/04_09_agent_observation/event_probe.ex)
collects SDK events for the parent and both child IDs.

```elixir
{:ok, parent} = Jido.start_agent(MyApp.Jido, Jido.Examples.CausalTrace, id: "trace-parent")
{:ok, _} = Jido.Examples.CausalTrace.start_work(parent, "request-1", 7)

# On a connected node with the same Jido instance and compiled Agent modules:
{:ok, parent} = Jido.start_agent(MyApp.Jido, Jido.Examples.CausalTrace, id: "remote-trace-parent")
{:ok, _} = Jido.Examples.CausalTrace.start_work(parent, "request-2", 7,
  input: %{node: target_node})
```

Both cases produce `%{left: 14, right: 14}` in the parent's result state.
The tests assert the actual remote child PIDs as well as their trace links.

## Core change

`SpawnAgent` captures a private creation cause from the spawning Turn. It contains
only the trace ID, span ID, Signal ID, and Turn ID. The cause travels with child
startup options, the parent relationship, and any unresolved remote request.
A bounded internal identity query supplies the child's activation ID. Online
reports use verified child identity; tuple payloads do not supply the cause.
The existing parent, tag, target-node, and creation-request checks remain.

Both immediate and delayed notifications use the same Signal builder. Each gets
a new Signal ID and span, under the original creation trace and span. Child
activation and stop events also carry that lifecycle cause. An OTP restart has
a new activation ID. Explicit replacement captures a new creation cause.

| Field | Meaning |
| --- | --- |
| `trace_id`, `parent_span_id` | Trace and causal parent span |
| `causation_id` | Signal that caused this work or lifecycle event |
| `cause_turn_id` | Spawning Turn, when a creation cause exists |
| `child_activation_id` | Child activation named by a child-start notification |
| `source_signal_id` | Signal submitted to the observed Turn; unchanged |

Later business commands use their own incoming traces. A caller can explicitly
link a retry with `Jido.Tracing.Trace.child_of/2`; that retry has a new Signal,
Turn, and span identity. The runtime does not infer business retry relationships.

## Acceptance evidence

```shell
mix test test/jido/observe/causal_trace_test.exs test/jido/observe/remote_causal_trace_test.exs --seed 0
```

| Requirement | Evidence |
| --- | --- |
| Pure evaluation | Returns candidate state and four Directives, with no runtime events or generated trace fields |
| Work and result causality | Two children share the initiating trace; work/result Signal, Turn, and span IDs remain distinct |
| Local and remote child start | Activation and notification events identify the spawning Signal and Turn |
| Delayed start and request retry | A suspended remote supervisor forces two timed-out attempts; the eventual single child retains the first cause |
| OTP restart | Local and remote restart retain the cause with new activation, Signal, and span IDs |
| Local process restore | The runtime relationship binding retains the cause after child process loss |
| Explicit replacement | A new creation command establishes a new cause |
| Missing saved cause | An older relationship without a cause keeps root behavior |
| Independent command and explicit retry | New work does not inherit the creation trace; a caller-linked retry retains its failed attempt's trace |
| Failed startup | The attempt reports a failed Directive and terminal Turn; no child activation or start event is invented |
| Privacy | Semantic events exclude private state and Signal payloads |

The two-node tests use independent standard IO channels for setup and test
inspection. Agent creation and Signal delivery use real Erlang distribution.
The collectors copy semantic `[:jido, :agent, ...]` events. They do not read debug
history or derive events from command results.

## Limits

The runtime relationship store survives individual Agent process loss but ends
with its Jido instance. Creation causes are not saved in durable Agent
checkpoints. Cause recovery after Jido instance or VM loss is not claimed.

The finite EventProbe does not implement the bounded consumer or waiting-reason
contract planned under OBS-03. Creation causation does not establish distributed
writer authority, delivery guarantees, or automatic business retries.

## Validation

The focused OBS-02 run reports **12 passing tests, no failures or skips**. A
separate current run of Basic through Multi-agent reports **170 passing tests,
no failures or skips**. `mix quality` passes warnings-as-errors compilation,
Credo, and Dialyzer with zero errors. `mix docs --no-open`, local Markdown links,
formatting, and Git whitespace checks pass.

The distribution regression result and new DIST-03 boundary are recorded in
the [DIST-03 report](dist-03-results.md). The separate full-suite gaps remain in
the [gap register](runtime-multi-agent-gaps.md).
