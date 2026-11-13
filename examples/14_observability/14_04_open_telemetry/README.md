# 14_04 OpenTelemetry Integration

A host-managed OpenTelemetry tracer receives Jido spans without a remote
collector.

## What you will learn

- How `Jido.Telemetry.open_telemetry?/0` reports an active host tracer.
- How Jido maps normal runtime work to OpenTelemetry spans automatically.
- Which tracer, processor, sampler, exporter, and credentials the host owns.

## Read the code

Read [the traced Agent](traced_agent.ex), then the bounded
[offline tracer](offline_tracer.ex), and then the test setup.

## Run it

`mix test.examples examples/14_observability/14_04_open_telemetry --warnings-as-errors`

Expected result: the host tracer receives and ends a
`jido.agent_server.turn` span with the logical Agent ID.

## Important behavior

Jido uses the active OpenTelemetry API tracer. It does not start an SDK,
select a sampler, or configure a network exporter. The offline tracer is a
small host fixture that records spans in the test process.

## Limits

This lesson does not prove batching, sampling, exporter retries, collector
authentication, or remote delivery.

## Core Fit and Gaps

The automatic span bridge composes without changes to Agent code. Production
SDK and exporter operation remain host responsibilities. The public Jido API
reports whether the bridge is active, but it does not expose bridge internals.

## Files

- [Agent](traced_agent.ex)
- [Offline tracer](offline_tracer.ex)
- [Tests](open_telemetry_test.exs)

Previous: [Causal Trace](../14_03_causal_trace/README.md) |
Next: [Runtime Timeline](../14_05_runtime_timeline/README.md)
