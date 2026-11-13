# 25_02 Persistence adapter selection

This lesson validates explicit, disabled, and instance-owned persistence sources.

## What you will learn

- Persistence selection is explicit and can be inherited from a Jido instance.
- Adapter validation does not prove service durability or availability.

## Read the code

Read [the selection boundary](persistence_selection.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_02_persistence_selection --warnings-as-errors`

Expected result: ETS resolves locally, `nil` stays disabled, inherited config
matches the live instance, and an invalid adapter is rejected.

## Important behavior

ETS is an in-memory development and test adapter. It does not survive BEAM loss.

## Limits

This lesson does not contact Redis, S3, Ecto, Bedrock, or another external store.

## Core Fit and Gaps

The public persistence resolver makes adapter ownership clear. Each real
adapter must document atomic writes, uncertain outcomes, credentials,
availability, and cleanup.

## Files

- [Source](persistence_selection.ex)
- [Tests](persistence_selection_test.exs)

[Previous: Production configuration](../25_01_production_configuration/README.md)

[Next: Credential boundaries](../25_03_credential_boundaries/README.md)
