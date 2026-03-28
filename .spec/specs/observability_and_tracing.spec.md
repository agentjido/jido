# Observability And Tracing

Current-truth contract for telemetry, observation, and trace propagation in Jido.

## Intent

This subject covers how Jido makes agent execution observable in production through structured events, telemetry, and trace context.

```spec-meta
id: jido.observability_and_tracing
kind: subsystem
status: active
summary: Jido exposes production observability through structured telemetry, observation, and tracing.
surface:
  - guides/observability-intro.md
  - guides/observability.md
  - lib/jido/observe.ex
  - lib/jido/observe
  - lib/jido/telemetry.ex
  - lib/jido/telemetry
  - lib/jido/tracing
  - test/examples/observability
  - test/jido/observe
  - test/jido/telemetry_test.exs
  - test/jido/tracing
```

## Requirements

```spec-requirements
- id: jido.observability_and_tracing.telemetry_contract
  statement: Jido shall emit structured observability and telemetry events for agent and pod execution.
  priority: must
  stability: stable

- id: jido.observability_and_tracing.tracing_context
  statement: Jido shall preserve trace and span context across runtime execution and signal flow.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/observability.md
  covers:
    - jido.observability_and_tracing.telemetry_contract
    - jido.observability_and_tracing.tracing_context

- kind: command
  target: mix test test/jido/observe test/jido/telemetry_test.exs test/jido/tracing test/examples/observability/observability_test.exs test/examples/observability/tracing_test.exs test/examples/observability/domain_event_observability_test.exs
  execute: true
  covers:
    - jido.observability_and_tracing.telemetry_contract
    - jido.observability_and_tracing.tracing_context
```
