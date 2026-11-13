# 14_02 Metrics

A host reporter uses `Jido.Telemetry.metrics/0` to count Turns and summarize
their duration.

## What you will learn

- How to read the public low-cardinality metric catalog.
- How a metric definition maps to one semantic telemetry event.
- Why IDs and error text are not metric tags.

## Read the code

Read [the metric projection and Agent](metrics.ex), then the local reporter in
the behavior test.

## Run it

`mix test.examples examples/14_observability/14_02_metrics --warnings-as-errors`

Expected result: the reporter receives one successful Turn event with a
duration, `status: :ok`, and `stage: :commit`.

## Important behavior

Jido supplies metric definitions. The host application selects and supervises
the reporter. Metric tags use bounded status, stage, and operation values.
Agent, Signal, trace, module, and error identifiers are not tags.

## Limits

The test reporter receives one event in the caller process. It does not prove
aggregation accuracy, exporter capacity, backpressure, or remote delivery.

## Core Fit and Gaps

The public catalog composes with any `Telemetry.Metrics` compatible reporter.
Reporter lifecycle, storage, alert rules, and export remain host concerns.

## Files

- [Source](metrics.ex)
- [Tests](metrics_test.exs)

Previous: [Semantic Telemetry](../14_01_semantic_telemetry/README.md) |
Next: [Causal Trace](../14_03_causal_trace/README.md)
