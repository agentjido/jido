# 08_07 Trace and Causation

One request, child Signal, and reply share a trace and correlation ID while
each edge records its direct cause.

## What you will learn

- How `Jido.Trace.child/2` creates parent and child span relationships.
- How `Jido.Signal.Context` carries trace, causation, and correlation data.

## Read the code

Read [the Signal journey](trace_and_causation.ex), then read
[the tests](trace_and_causation_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_07_trace_and_causation --warnings-as-errors`

Expected result: all three Signals share one trace ID and correlation ID. Each
child names the Signal that caused it.

## Important behavior

Correlation groups related work. Causation identifies the direct prior event.
They are not interchangeable. W3C `traceparent` carries the current span. The
local `parent_span_id` remains part of the trace link that created that span;
it is not a separate field in the downstream carrier.

## Limits

This lesson builds the journey as values. It does not deliver the Signals or
start Agents.

## Core Fit and Gaps

Trace and context values compose without a process. The correlation extension
name is application-owned; Jido gives it validation but no higher-level
correlation API.

## Files

- [Signal journey](trace_and_causation.ex)
- [Tests](trace_and_causation_test.exs)
