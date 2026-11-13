# 18_01 Retry and fallback

This ReAct Agent distinguishes retryable provider failure from authorization
failure and applies ordered fallback within explicit budgets.

## What you will learn

- How ReAct records each model attempt, error category, and retryability.
- How fallback uses the next named model only after a retryable failure.
- How the model-call budget stops work before another attempt.

## Read the code

Read [the shared bounded Agent](../support/resilient_agent.ex), then read the
[scripted inference client](../support/scripted_inference_client.ex).

## Run it

`mix test.examples examples/18_model_resilience/18_01_retry_and_fallback --warnings-as-errors`

Expected result: a rate limit uses the fallback, an authorization error fails
without fallback, and a one-call budget blocks before fallback.

## Important behavior

The result records the selected model, attempts, usage, and retry count. Error
records do not contain the fixture credential. Retry and fallback are ReAct
behavior. Other reasoning strategies do not inherit this behavior.

## Limits

The offline client does not prove provider compatibility, latency, billing, or
credential validity. The example has no circuit breaker, hedge, or provider
health router.

## Core Fit and Gaps

ReAct exposes explicit fallback and attempt records through the public Agent
reply. Request limits bound the retry boundary. The application must confirm
that fallback models have compatible capabilities and valid credentials.

## Files

- [Tests](retry_and_fallback_test.exs)
- [Agent](../support/resilient_agent.ex)
- [Offline client](../support/scripted_inference_client.ex)

[Next: Repair and budgets](../18_02_repair_and_budgets/README.md)
