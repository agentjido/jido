# 25_08 Offline AI provider configuration and failure

This lesson selects an inference client through runtime context and tests a
safe missing-credential failure without a live provider.

## What you will learn

- Provider client configuration stays outside Agent state, Signals, and Sessions.
- Invalid credentials are not retryable and must not trigger a fallback.
- Safe result data does not retain provider request credential material.

## Read the code

Read [the configured Agent and runtime boundary](offline_provider_configuration.ex),
then read the [failure client](support/missing_credentials_client.ex).

## Run it

`mix test.examples examples/25_operations_and_integrations/25_08_offline_provider_configuration --warnings-as-errors`

Expected result: the normal offline client completes. The missing-credential
client fails once with no retry and no fake secret in the Reply data.

## Important behavior

The same public AI Agent and ReAct Flow run in both cases. Only the temporary
inference client changes.

## Limits

This lesson does not read or validate a live credential. ReqLLM owns provider
credential resolution. No live provider, fallback provider, or network is used.

## Core Fit and Gaps

The public inference-client boundary and execution context are sufficient.
Jido core does not need a second provider-key configuration. The host must own
secret retrieval, rotation, least privilege, and tenant scope.

## Files

- [Source](offline_provider_configuration.ex)
- [Tests](offline_provider_configuration_test.exs)
- [Missing-credential client](support/missing_credentials_client.ex)
- [Shared offline client](../../support/offline_inference_client.ex)

[Previous: Distribution boundaries](../25_07_distribution_boundaries/README.md)
