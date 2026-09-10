# 03_06 Output repair

This example treats invalid model output as data for a bounded repair loop.

## What you will learn

- How Flow Iterate keeps explicit repair state.
- How schema issues can guide the next model request without causing an
  unbounded retry loop.

## Read the code

Read [the Agent and repair Flow](output_repair.ex), then the shared
[LLM adapter](../support/adapter.ex).

## Run it

```sh
mix test test/examples/03_llm/03_06_output_repair --include example --seed 0
```

Expected result: a valid answer needs one call, invalid model data can use at
most two repair calls, and provider failures are not retried.

## Important behavior

Only output-schema failures enter the repair loop. The loop sends validation
feedback to the next model call and stops after three total attempts. A failed
Turn preserves the prior Agent state.

## Limits

The feedback is a local schema issue description. This example does not define
provider prompts, backoff, rate-limit policy, or durable retry state.

## Files

- [Agent and Flow with inline Actions](output_repair.ex)
- [Shared LLM adapter](../support/adapter.ex)
- [Tests](../../../test/examples/03_llm/03_06_output_repair/output_repair_test.exs)

Previous: [Parallel Tools](../03_05_parallel_tools/README.md) | Next: [Runtime examples](../../04_runtime/README.md)
