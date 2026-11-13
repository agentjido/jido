# 25_05 Passive Agent Fleet measurement

This lesson measures a bounded local fleet from logical creation through
activation and passivation.

## What you will learn

- Logical Agent count and resident process count are different measurements.
- A useful report publishes environment, store, concurrency, latency
  percentiles, throughput, and memory samples.

## Read the code

Read [the measured Agent and report builder](passive_fleet_measurement.ex) first.

## Run it

```sh
mix test.examples examples/25_operations_and_integrations/25_05_passive_fleet_measurement --warnings-as-errors
mix run examples/25_operations_and_integrations/25_05_passive_fleet_measurement/benchmark.exs
```

Expected result: the test measures 8 logical Agents with concurrency 4. The
runner prints a 50-Agent report with the current machine environment.

## Important behavior

Processes are disposable; logical Agent identity and state remain in the ETS
store through passivation.

## Limits

This is a bounded local measurement, not a capacity or density claim. ETS is
not a shared durable store. Total BEAM memory includes unrelated work. Cluster
placement, sustained load, and maximum density are not measured.

## Core Fit and Gaps

Public Refs, resident counts, calls, and passivation support a reproducible
local report. Jido has no public logical-Agent listing API, so the application
must retain its created Ref inventory. Scale claims require a separate
controlled benchmark and published evidence.

## Files

- [Source](passive_fleet_measurement.ex)
- [Tests](passive_fleet_measurement_test.exs)
- [Runner](benchmark.exs)

[Previous: External adapter boundary](../25_04_external_adapter_boundary/README.md)

[Next: Security boundaries](../25_06_security_boundaries/README.md)
