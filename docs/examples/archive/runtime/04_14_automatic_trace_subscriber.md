> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Automatic Trace Subscriber

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_14_automatic_trace_subscriber`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Observability
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Attach one read-only subscriber that records the complete Agent execution shape without changing behavior.
- **User story:** As an operator, I see sessions, Signals, Turns, model calls, tool calls, Flow steps, runtime commands, retries, and compaction in one trace.
- **Trigger or input:** One ReAct Signal plus model, tool, Directive, retry, and completion events from the local scenario.
- **Agent state:** Domain state has no tracer fields. The observer owns only transient export buffers and trace-delivery state.
- **Actions or Flow:** The ReAct Flow is unchanged. The subscriber receives typed lifecycle events from runtime and explicitly instrumented effect adapters.
- **External interactions:** Fake trace exporter that records spans, attributes, errors, token data, and redaction decisions.
- **Runtime Directives or capabilities:** Trace delivery is observer-owned work. A failed exporter must not change or stop the Actor Turn.
- **Expected result:** The trace has one session root, one Signal and Turn path, nested model and tool work, runtime outcomes, and one terminal status. Sensitive payload fields are absent.
- **Failure cases:** Exporter unavailable, late span, duplicate event, missing parent, oversized payload, secret field, incomplete Turn, retry, or observer shutdown.
- **Jido features under pressure:** Typed lifecycle events, trace context, read-only subscribers, effect instrumentation, redaction, failure isolation, and shutdown flushing.
- **Source framework and links:** [Pi Raindrop extension](https://pi.dev/packages/@raindrop-ai/pi-agent), [Pi Braintrust extension](https://pi.dev/packages/@braintrust/pi-extension), and [Pi extension lifecycle events](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md)

## Smallest missing contract

Jido has tracing primitives, but the example needs one stable public event
stream for the complete Signal, Turn, Flow, effect-adapter, Directive, retry,
and shutdown lifecycle. The subscriber must be read-only and fail open.


## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_14_automatic_trace_subscriber/automatic_trace_subscriber.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_14_automatic_trace_subscriber/automatic_trace_subscriber_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: A complete read-only Signal, Turn, Flow, effect, Directive, retry, and shutdown event stream is missing.

An example-scope gap is not evidence of a core Jido defect.
