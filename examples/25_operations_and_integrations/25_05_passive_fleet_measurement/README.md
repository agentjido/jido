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

Public Addresses, resident counts, calls, and passivation support a reproducible
local report. Jido has no public logical-Agent listing API, so the application
must retain its created Address inventory. Scale claims require a separate
controlled benchmark and published evidence.

- Logical owner: the application-owned inventory of stable Agent Addresses.
- Process owner: the Jido instance owns each current activation.
- Canonical state owner: each Agent record in the configured ETS store.
- Commit point: each measured Agent call commits its own state and revision.
- Persisted data: Agent state and revisions remain in ETS for the BEAM lifetime.
- Retry boundary: none; the measurement sends one call to each Agent.
- Idempotency rule: none; the benchmark does not repeat delivery.
- Injected failure: none; the test forces idle passivation as a lifecycle event.
- Recovery result: later activation loads the same logical Agent state.
- Limits and non-guarantees: the report is not a capacity, cluster, or
  host-loss durability claim.

## Files

- [Source](passive_fleet_measurement.ex)
- [Tests](passive_fleet_measurement_test.exs)
- [Runner](benchmark.exs)

[Previous: External adapter boundary](../25_04_external_adapter_boundary/README.md)

[Next: Security boundaries](../25_06_security_boundaries/README.md)
