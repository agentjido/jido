# 14_07 Safe Metadata

Semantic telemetry identifies runtime work without copying Signal data or
committed Agent state.

## What you will learn

- Which logical IDs can correlate a Turn safely.
- Why credentials, prompts, model input, Signal data, errors, and Agent state
  must not become telemetry metadata.
- Why audit records and observability events have different ownership.

## Read the code

Read [the Agent with sensitive data](safe_metadata.ex), then the external event
probe assertions.

## Run it

`mix test.examples examples/14_observability/14_07_safe_metadata --warnings-as-errors`

Expected result: the secret is present in committed domain state and absent
from every captured semantic event.

## Important behavior

Jido telemetry uses a strict scalar allowlist. It can include logical Agent,
Turn, Signal, trace, and activation identifiers for correlation. It excludes
the Signal payload, Agent and Plugin state, complete error values, process
handles, and caller context.

## Limits

The test checks Jido semantic events. Application telemetry, logger messages,
custom exporters, and external libraries need their own data policy.

## Core Fit and Gaps

The core allowlist gives a safe default for Jido-owned events. Application
events still need explicit field review, redaction tests, and retention rules.
A durable audit record is application state; telemetry is best effort.

## Files

- [Source](safe_metadata.ex)
- [Tests](safe_metadata_test.exs)
- [Shared event probe](../support/event_probe.ex)

Previous: [Failed Turn Debugging](../14_06_failed_turn_debugging/README.md) |
Next: [Activation Measurements](../14_08_activation_measurements/README.md)
