# 17_02 Linear reasoning comparison

This Flow runs Chain of Thought, Chain of Draft, and Algorithm of Thoughts over
one offline case and compares their structured results.

## What you will learn

- Each reasoning strategy is a normal Jido Flow with a public result contract.
- These linear strategies use one bounded model call but preserve different
  reasoning data.

## Read the code

Read [the comparison Flow](linear_reasoning_comparison.ex) first.

## Run it

`mix test.examples examples/17_ai_reasoning_flows/17_02_linear_reasoning_comparison --warnings-as-errors`

Expected result: all three branches return `42`, and each branch records its
own reasoning shape and one model call.

## Important behavior

The outer Flow calls each reasoning Flow as a bounded subflow. The strategies
share application input but not mutable state. Each step has an explicit
offline structured result.

## Limits

The fixtures prove Flow composition and output contracts. They do not compare
model quality, hidden model reasoning, latency, or cost.

## Core Fit and Gaps

Normal Flow composition and the inference-client boundary are sufficient. The
application owns the comparison case and fixture. A useful quality comparison
still needs a dataset, repeat runs, scoring, and measured provider evidence.
That is application evaluation work, not a new reasoning runtime.

## Files

- [Source](linear_reasoning_comparison.ex)
- [Tests](linear_reasoning_comparison_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: ReAct tool loop](../17_01_react_tool_loop/README.md)

[Next: Branching reasoning comparison](../17_03_branching_reasoning_comparison/README.md)
