# 17_04 Revision and adaptive reasoning

This Flow compares one bounded draft-critique-revision cycle with local
selection of an existing reasoning Flow.

## What you will learn

- TRM owns three explicit model phases and one revision iteration.
- Adaptive uses a local decision to select a trusted reasoning Flow. It does
  not let model output select an arbitrary module.

## Read the code

Read [the comparison Flow](revision_and_adaptive.ex) first.

## Run it

`mix test.examples examples/17_ai_reasoning_flows/17_04_revision_and_adaptive --warnings-as-errors`

Expected result: TRM records its draft and critique before it returns the
revision, while Adaptive selects Chain of Draft and uses one model call.

## Important behavior

Both paths have explicit call bounds. Adaptive selection is local and maps a
known strategy name to a trusted Flow module.

## Limits

The deterministic fixtures prove selection and phase behavior. They do not
prove that revision improves quality or that the adaptive heuristic fits a
production workload.

## Core Fit and Gaps

`Invoke` and normal reasoning Flows provide the required selection boundary.
The application owns strategy policy and evaluation. A production policy must
measure quality, cost, latency, and failure by case type before it claims that
adaptive selection is useful.

## Files

- [Source](revision_and_adaptive.ex)
- [Tests](revision_and_adaptive_test.exs)
- [Structured offline client](../support/structured_reasoning_client.ex)

[Previous: Branching reasoning comparison](../17_03_branching_reasoning_comparison/README.md)

[Next: Custom reasoning Flow](../17_05_custom_reasoning_flow/README.md)
