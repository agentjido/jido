# 14_08 Activation Measurements

A bounded report separates logical Agent count from resident process count and
records activation latency, passivation time, memory, and store operations.

## What you will learn

- How durable logical Agents can exist with no resident activation process.
- How to measure activation and passivation through public APIs.
- Which inputs and runtime environment a repeatable report must publish.

## Read the code

Read [the measured Agent and report builder](activation_measurements.ex), then
the bounded 12-Agent test.

## Run it

`mix test.examples examples/14_observability/14_08_activation_measurements --warnings-as-errors`

Expected result: 12 logical Agents start with zero residents, become 12
residents during work, return to zero, and one Agent later receives a new
activation identity with its committed state intact.

## Important behavior

The report records Elixir, OTP, scheduler count, sample count, latency
percentiles, passivation time, total BEAM memory samples, and semantic
persistence-operation events. Logical Agent identity survives each activation
process.

## Limits

This is a bounded integration measurement, not a capacity claim. Total BEAM
memory includes unrelated runtime work. The test does not measure a shared
store, sustained throughput, cluster placement, or maximum Agent density.

## Core Fit and Gaps

Public Refs, status, resident counts, and telemetry support honest local
measurement. There is no public logical-Agent listing API, so the application
must keep its own inventory of created Refs. Store event counts show load, but
adapter-specific latency and capacity need adapter instrumentation.

## Files

- [Source](activation_measurements.ex)
- [Tests](activation_measurements_test.exs)
- [Shared event probe](../support/event_probe.ex)

Previous: [Safe Metadata](../14_07_safe_metadata/README.md) |
Next: [AI Agents](../../15_ai_agents/README.md)
