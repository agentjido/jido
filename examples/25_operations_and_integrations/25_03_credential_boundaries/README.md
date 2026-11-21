# 25_03 Secrets and credential boundaries

This lesson checks a fake runtime credential without placing it in Jido data.

## What you will learn

- Credentials belong in runtime configuration or a host secret provider.
- Signals, Flow input, Agent state, Sessions, snapshots, telemetry, and result
  data must not contain credential material.
- Provider request options are normal Flow input, not a secret channel.

## Read the code

Read [the preflight Action](credential_boundaries.ex) first.

## Run it

`mix test.examples examples/25_operations_and_integrations/25_03_credential_boundaries --warnings-as-errors`

Expected result: valid fake input returns only safe readiness data. Missing and
invalid input return the same redacted reason.

## Important behavior

One Action uses the same canonical one-step Flow execution model. The fake
credential exists only in temporary execution context.

## Limits

This example does not resolve a live provider key. ReqLLM owns model-provider
credential resolution. Rotation, tenant isolation, and least privilege depend
on the host secret system and provider account.

## Core Fit and Gaps

Jido needs no provider-key setting. Execution context is sufficient for an
application preflight, but redaction is defense in depth and is not proof that
a leaked value is safe.

## Files

- [Source](credential_boundaries.ex)
- [Tests](credential_boundaries_test.exs)

[Previous: Persistence selection](../25_02_persistence_selection/README.md)

[Next: External adapter boundary](../25_04_external_adapter_boundary/README.md)
