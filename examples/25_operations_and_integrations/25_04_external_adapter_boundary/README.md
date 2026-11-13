# 25_04 External adapter boundaries

This lesson runs one delivery Flow against a deterministic local service port.

## What you will learn

- The application owns the external-service behavior and adapter contract.
- Runtime adapters belong in execution context, not Agent state or Signals.
- Missing and rejected adapters produce explicit Flow errors.

## Read the code

Read [the port, local service, Action, and Flow](external_adapter_boundary.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_04_external_adapter_boundary --warnings-as-errors`

Expected result: the local service returns a stable receipt, while missing and
rejected adapters fail without a network request.

## Important behavior

The Flow boundary stays the same when a production adapter replaces the local
fixture. The adapter must keep idempotency and uncertainty semantics explicit.

## Limits

The local service does not prove network timeouts, authentication, remote
deduplication, or recovery from an uncertain outcome.

## Core Fit and Gaps

Normal Actions, Flows, and execution context are sufficient. The external
system contract belongs to the application or an ecosystem package, not Jido core.

## Files

- [Source](external_adapter_boundary.ex)
- [Tests](external_adapter_boundary_test.exs)

[Previous: Credential boundaries](../25_03_credential_boundaries/README.md)

[Next: Passive Agent Fleet measurement](../25_05_passive_fleet_measurement/README.md)
