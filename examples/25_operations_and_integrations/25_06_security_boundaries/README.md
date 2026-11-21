# 25_06 Security, authorization, and sandbox limits

This lesson authorizes one allowlisted operation before a simulated effect.

## What you will learn

- Authentication and tenant authorization belong before sensitive work.
- A strict input schema can limit selectable operations.
- Jido does not sandbox arbitrary Action code or make an Agent Address a credential.

## Read the code

Read [the authorization and operation Flow](security_boundaries.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_06_security_boundaries --warnings-as-errors`

Expected result: the correct tenant operator succeeds. Missing identity, wrong
tenant, insufficient role, and an unknown operation fail before execution.

## Important behavior

Authorization data stays in execution context. The example does not put a
principal or access token in portable Agent state.

## Limits

The operation is simulated. A real command or tool needs OS isolation,
resource limits, network policy, path controls, and audit outside Jido core.

## Core Fit and Gaps

Normal Actions and Flows express application policy. Jido does not provide an
authorization server or process sandbox. Those remain host and application
security responsibilities.

## Files

- [Source](security_boundaries.ex)
- [Tests](security_boundaries_test.exs)

[Previous: Passive Agent Fleet measurement](../25_05_passive_fleet_measurement/README.md)

[Next: Distribution boundaries](../25_07_distribution_boundaries/README.md)
