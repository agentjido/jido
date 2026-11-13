# 25_01 Production configuration and shutdown

This lesson starts a declared Jido instance, commits one Turn, and shuts down
the complete supervised Agent tree.

## What you will learn

- A host OTP application declares one named Jido supervision root.
- Runtime overrides belong at supervisor startup, not in Agent state.
- Stopping the Jido instance terminates its resident Agent processes.

## Read the code

Read [the configured runtime and Agent](production_configuration.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_01_production_configuration --warnings-as-errors`

Expected result: one Turn commits, then the Jido supervisor and AgentServer stop.

## Important behavior

The logical Agent value and its process are different concerns. This lesson
uses no persistence, so shutdown does not promise later activation.

## Limits

The test does not drain external traffic, coordinate a cluster, or prove a
deployment platform shutdown timeout.

## Core Fit and Gaps

OTP supervision and the public Jido instance API compose cleanly. A production
host must still order traffic draining, quiesce, persistence, and supervisor
shutdown for its deployment environment.

## Files

- [Source](production_configuration.ex)
- [Tests](production_configuration_test.exs)

[Next: Persistence adapter selection](../25_02_persistence_selection/README.md)
