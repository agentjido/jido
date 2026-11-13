# 14_06 Failed Turn Debugging

A bad external Signal fails before commit, and public result, status, and
telemetry data agree on the outcome.

## What you will learn

- How generated Signal constructors build envelopes without running an Action
  input schema.
- How the hosted route validates that input before commit.
- How to compare `TurnResult`, `AgentServer.Status`, snapshot revision, and a
  settled telemetry event.

## Read the code

Read [the validated Agent](failed_turn.ex), then the synchronized failure proof.

## Run it

`mix test.examples examples/14_observability/14_06_failed_turn_debugging --warnings-as-errors`

Expected result: the Turn returns `status: :failed`, revision stays zero, and
telemetry reports `committed?: false`.

## Important behavior

The generated helper validates the Signal contract, not the later Action input
contract. The detailed execution error belongs to the direct `TurnResult`.
Operational status keeps only a safe bounded outcome. Telemetry reports
classifying fields and does not copy the complete error or Agent state.

## Limits

This lesson covers route-input validation before commit. It does not cover a
crash during persistence or an effect failure after commit.

## Core Fit and Gaps

The three public surfaces give consistent failure evidence. The difference
between Signal construction and Action-input validation is a documentation
boundary that client authors must understand. A production incident timeline
still needs a host collector and retention policy.

## Files

- [Source](failed_turn.ex)
- [Tests](failed_turn_test.exs)
- [Shared event probe](../support/event_probe.ex)

Previous: [Runtime Timeline](../14_05_runtime_timeline/README.md) |
Next: [Safe Metadata](../14_07_safe_metadata/README.md)
