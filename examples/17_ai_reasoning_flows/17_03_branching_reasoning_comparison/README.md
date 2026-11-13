# 17_03 Branching reasoning comparison

This Flow compares a candidate tree with a relationship graph by using one
deterministic offline case.

## What you will learn

- Tree of Thoughts generates, scores, selects, and synthesizes candidates in
  three bounded model calls.
- Graph of Thoughts builds nodes and edges, then synthesizes in two bounded
  model calls.

## Read the code

Read [the comparison Flow](branching_reasoning_comparison.ex), then read the
[structured offline client](../support/structured_reasoning_client.ex).

## Run it

`mix test.examples examples/17_ai_reasoning_flows/17_03_branching_reasoning_comparison --warnings-as-errors`

Expected result: the tree keeps three scored candidates and the graph keeps
two related nodes before both return a final answer.

## Important behavior

The offline client selects each phase fixture from the strategy option and the
public structured-output schema. It uses no provider, global mock, or private
runtime state.

## Limits

The example proves graph shape, phase bounds, and result data. It does not
show that branching produces a better answer than a linear strategy.

## Core Fit and Gaps

Normal Flows, nested Flow calls, and structured model output compose cleanly.
The application must still decide when the added calls, latency, and cost are
justified. Quality and scale claims require measured evaluation data.

## Files

- [Source](branching_reasoning_comparison.ex)
- [Tests](branching_reasoning_comparison_test.exs)
- [Structured offline client](../support/structured_reasoning_client.ex)

[Previous: Linear reasoning comparison](../17_02_linear_reasoning_comparison/README.md)

[Next: Revision and adaptive reasoning](../17_04_revision_and_adaptive/README.md)
