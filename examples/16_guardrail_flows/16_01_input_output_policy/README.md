# 16_01 Input and output policy

This Flow checks model input and output and returns an application-owned audit
record. It compares fail-open and fail-closed handling without hidden
middleware.

## What you will learn

- How Actions protect the model input and output boundaries.
- How PII, prompt-injection, moderation, and output findings stop or annotate a
  request.
- How to select a deterministic `Jido.AI.InferenceClient` through context.

## Read the code

Read [the Flow and policy Actions](input_output_policy.ex) first. Then read the
[offline inference client](../../support/offline_inference_client.ex).

## Run it

`mix test.examples examples/16_guardrail_flows/16_01_input_output_policy --warnings-as-errors`

Expected result: four tests pass without a network request. Safe input returns
an answer and audit evidence. Rejected input or output returns a validation
error at its protected boundary.

## Important behavior

Fail-closed handling stops before inference. Fail-open handling redacts a
detected email and records the findings. Output checks run before the result is
returned for application use. The audit record contains decisions, findings,
a digest, and trace context. It does not contain the original input.

## Limits

The pattern checks a small deterministic rule set. It does not prove the
quality of a production PII, injection, or moderation detector. Fail-open can
pass harmful content and must be an explicit application decision.

## Core Fit and Gaps

Actions and Flow references make each policy boundary and failure path clear.
Inference-client selection lets the same application boundary use an offline
client. The application owns redaction, policy results, and audit evidence.
Jido core does not supply guardrail policy or an audit-store contract. No new
core API is required by this example.

## Files

- [Source](input_output_policy.ex)
- [Tests](input_output_policy_test.exs)
- [Offline inference client](../../support/offline_inference_client.ex)

[Next: Tool boundary policy](../16_02_tool_boundary_policy/README.md)
