# 03_01 Model response

This example makes one typed model call and commits only the selected answer.

## What you will learn

- How an inline Action uses a transient model client from Turn context.
- How application fallback policy treats only selected errors as transient.

## Read the code

Read [the Agent](model_response.ex) first. Then read the shared
[LLM adapter contract](../support/adapter.ex).

## Run it

```sh
mix test test/examples/03_llm/03_01_model_response --include example --seed 0
```

Expected result: a valid response commits one answer. Invalid input makes no
provider call, and invalid output does not replace prior state.

## Important behavior

The model and backup clients stay in Turn context. The fallback runs only for
timeout, overload, and rate-limit errors. Provider calls that finish before a
later validation failure are external effects and cannot be undone.

## Limits

The deterministic test adapter does not prove provider compatibility, model
quality, or retry safety.

## Files

- [Agent and inline Action](model_response.ex)
- [Shared LLM adapter](../support/adapter.ex)
- [Tests](../../../test/examples/03_llm/03_01_model_response/model_response_test.exs)

Previous: [Approval Workflow](../../02_workflow/02_09_approval_workflow/README.md) | Next: [Conversation History](../03_02_conversation_history/README.md)
