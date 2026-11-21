# 18_03 Failure matrix

This offline matrix checks stable results for success, rate limits,
authorization failure, repair, output limits, partial streams, and tool
failure.

## What you will learn

- How a tool failure becomes bounded, safe model input.
- How deterministic provider cases form an offline regression matrix.
- How a partial stream fails without committing an assistant message.
- How hosted Agent telemetry reports status without prompt or output content.

## Read the code

Read [the matrix tests](failure_matrix_test.exs), then read the
[scripted inference client](../support/scripted_inference_client.ex).

## Run it

`mix test.examples examples/18_model_resilience/18_03_failure_matrix --warnings-as-errors`

Expected result: each scripted model name produces the stated status and call
count. The tool-error request completes with a safe error result. Two bounded
partial-stream events precede one failure without an assistant commit.

## Important behavior

Every case has a bounded number of model and tool calls. Attempt records keep
model, usage, and safe error data. Hosted Agent telemetry has duration, model
call count, and final status, but not prompt or output content.

## Limits

The matrix does not open a network connection or test a provider SDK. The
partial stream is an in-memory ReqLLM stream fixture. It proves Jido commit
behavior, not provider transport cleanup.

## Core Fit and Gaps

Public Agent replies and Session entries provide useful resilience evidence.
The custom inference-client boundary makes provider outcomes deterministic.
Public ReqLLM stream types are sufficient for the local partial-failure
fixture. Jido commits no incomplete assistant message. No new Jido core API is
required.

## Files

- [Tests](failure_matrix_test.exs)
- [Agent](../support/resilient_agent.ex)
- [Offline client](../support/scripted_inference_client.ex)

[Previous: Repair and budgets](../18_02_repair_and_budgets/README.md)
