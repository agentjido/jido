# 14 Observability

These offline lessons observe Jido through public semantic data.

1. [Semantic Telemetry](14_01_semantic_telemetry/README.md) separates Turn
   success from failure before commit.
2. [Metrics](14_02_metrics/README.md) maps the public metric catalog to a local
   reporter.
3. [Causal Trace](14_03_causal_trace/README.md) connects parent and child work
   with trace and causation data.
4. [OpenTelemetry Integration](14_04_open_telemetry/README.md) uses a
   host-managed offline tracer.
5. [Runtime Timeline](14_05_runtime_timeline/README.md) projects public status
   across idle, waiting, and committed states.
6. [Failed Turn Debugging](14_06_failed_turn_debugging/README.md) aligns the
   direct result, public status, snapshot revision, and telemetry outcome.
7. [Safe Metadata](14_07_safe_metadata/README.md) proves that semantic events
   exclude Signal data and Agent state.
8. [Activation Measurements](14_08_activation_measurements/README.md) records
   logical count, resident count, latency, memory, and store operations.

Run the current chapter with:

```sh
mix test.examples examples/14_observability --warnings-as-errors
```

Expected result: telemetry and trace proofs pass with no external collector.

## Limits

The local probes are test collectors. They do not prove exporter capacity,
backpressure, or remote trace delivery.
