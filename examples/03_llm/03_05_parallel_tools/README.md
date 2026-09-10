# 03_05 Parallel tools

This example runs a validated finite tool plan with bounded Flow Map workers.

## What you will learn

- How Flow Map applies the Agent execution concurrency limit.
- How result position restores call-ID correlation after parallel completion.

## Read the code

Read [the Agent and Flow](parallel_tools.ex), then the shared
[tool support](../support/tooling.ex) and
[LLM adapter](../support/adapter.ex).

## Run it

```sh
mix test test/examples/03_llm/03_05_parallel_tools --include example --seed 0
```

Expected result: tool workers overlap when permitted, results retain plan
order, and invalid plans start no tool effects.

## Important behavior

The Flow validates the complete plan before Map starts. Collected item errors
reach the final model call with their stable call IDs. Cancellation terminates
active tool workers and preserves the prior commit.

## Limits

The example uses one approved tool type and a finite plan of at most eight calls.

## Files

- [Agent and Flow](parallel_tools.ex)
- [Shared tool support](../support/tooling.ex)
- [Shared LLM adapter](../support/adapter.ex)
- [Tests](../../../test/examples/03_llm/03_05_parallel_tools/parallel_tools_test.exs)

Previous: [Tool Loop](../03_04_tool_loop/README.md) | Next: [Output Repair](../03_06_output_repair/README.md)
