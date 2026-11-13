# 18_02 Repair and budgets

This ReAct Agent compares output repair with a provider retry and shows that
token and model-call budgets still apply to repair work.

## What you will learn

- How a truncated or overlong answer creates an output-repair attempt.
- How partial output stays in attempt evidence but does not become the final
  assistant answer.
- How token use can block the next repair call.

## Read the code

Read [the tests](repair_and_budgets_test.exs), then read the
[scripted inference client](../support/scripted_inference_client.ex).

## Run it

`mix test.examples examples/18_model_resilience/18_02_repair_and_budgets --warnings-as-errors`

Expected result: truncation and output length each repair once. A small token
budget blocks before the second model call.

## Important behavior

Output repair adds a repair instruction and calls the model again. It is not a
transport retry. Both operations consume the same bounded model-call and token
budgets. Only the complete repaired answer enters the final result.

## Limits

The fixture uses fixed usage values. It does not estimate provider tokens,
cost, or elapsed time. Repair can still return a wrong answer.

## Core Fit and Gaps

ReAct keeps provider attempts, output repair, usage, and the final answer in
one public result. The application must choose limits that fit each model and
must not treat a valid shape as a correct answer.

## Files

- [Tests](repair_and_budgets_test.exs)
- [Agent](../support/resilient_agent.ex)
- [Offline client](../support/scripted_inference_client.ex)

[Previous: Retry and fallback](../18_01_retry_and_fallback/README.md)

[Next: Failure matrix](../18_03_failure_matrix/README.md)
