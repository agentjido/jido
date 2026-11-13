# 15_14 Offline Testing

A scripted inference client drives the same AI Agent through pure and hosted
execution without a provider, credential, network call, or global mock.

## What you will learn

- How to implement `Jido.AI.InferenceClient` as a deterministic test adapter.
- How execution context selects the adapter for one request.
- How pure `Agent.cmd/3` and AgentServer produce the same public conversation.
- How a handled provider error commits a blocked request outcome without an
  assistant answer.

## Read the code

Read [the Agent and scripted client](offline_testing.ex), then compare the pure
and hosted assertions.

## Run it

`mix test.examples examples/15_ai_agents/15_14_offline_testing --warnings-as-errors`

Expected result: pure and hosted execution return the same projected
conversation. A scripted rate-limit error commits a blocked outcome but no
assistant message.

## Important behavior

The test supplies its client in execution context. It does not change global
application configuration or replace a module. Request options are ordinary
Flow input and are not a credential channel. A handled model failure is a
domain outcome of the reasoning Flow, not an execution crash.

## Limits

The client proves Jido integration behavior, not provider encoding, transport,
stream ordering, model quality, usage accuracy, or live capability support.

## Core Fit and Gaps

Inference-client injection provides a clean offline test seam across pure and
hosted execution. Session entry IDs, run IDs, and timestamps are intentionally
nondeterministic, so parity checks should compare public projections and domain
outcomes. A full client must implement the complete callback contract, even
when one test uses only text generation. Shared test clients can contain that
boilerplate.

## Files

- [Source](offline_testing.ex)
- [Tests](offline_testing_test.exs)
- [Shared offline client](../../support/offline_inference_client.ex)

Previous: [Skills and Tool Sources](../15_13_skills_and_tool_sources/README.md) |
Next: [Guardrail Flows](../../16_guardrail_flows/README.md)
