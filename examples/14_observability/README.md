# 14 Observability

These offline lessons observe Jido through public semantic data.

1. [Semantic Telemetry](14_01_semantic_telemetry/README.md) separates Turn
   commit events from later effect failures.
2. Metrics are introduced by the telemetry demo. A focused metrics lesson
   remains to be added.
3. [Causal Trace](14_03_causal_trace/README.md) connects parent and child work
   with trace and causation data.
4. OpenTelemetry integration remains to be added with an offline exporter.
5. Runtime timelines remain to be added.
6. Failed-Turn debugging remains to be added.
7. Redaction and safe metadata remain to be added.
8. Activation and passivation measurements remain to be added.

Run the current chapter with:

```sh
mix test.examples examples/14_observability --warnings-as-errors
```

Expected result: telemetry and trace proofs pass with no external collector.

## Limits

The local probes are test collectors. They do not prove exporter capacity,
backpressure, or remote trace delivery.

