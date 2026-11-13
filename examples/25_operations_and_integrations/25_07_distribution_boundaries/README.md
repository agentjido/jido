# 25_07 Distribution boundaries

This lesson keeps logical Agent identity separate from local process location.

## What you will learn

- A Ref contains namespace, partition, and ID. It contains no PID, node, module,
  definition revision, or storage revision.
- The Ref survives local process shutdown and remains portable.
- A Ref identifies an Agent. It is not an authorization credential.

## Read the code

Read [the identity boundary](distribution_boundaries.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_07_distribution_boundaries --warnings-as-errors`

Expected result: a Ref round-trips before and after local AgentServer shutdown.

## Important behavior

The Agent identity survives the process. Process location remains runtime data.

## Limits

This lesson does not provide cluster discovery, leader election, sharding,
cross-node routing, split-brain control, or a shared persistence service.

## Core Fit and Gaps

The Ref contract is distribution-safe identity data. Node placement and remote
delivery require an explicit application or ecosystem topology. Jido does not
claim transparent distributed AgentServer ownership.

## Files

- [Source](distribution_boundaries.ex)
- [Tests](distribution_boundaries_test.exs)

[Previous: Security boundaries](../25_06_security_boundaries/README.md)

[Next: Offline provider configuration](../25_08_offline_provider_configuration/README.md)
