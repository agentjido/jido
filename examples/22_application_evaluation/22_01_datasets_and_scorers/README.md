# 22_01 Datasets and deterministic scorers

This example loads named JSON cases and scores exact output, status, citation,
and refusal behavior through a normal one-step Flow.

## What you will learn

- How fixture cases keep expected and actual application results together.
- How deterministic scorers produce visible checks and one aggregate score.
- How refusal and guardrail cases belong in the same regression dataset.

## Read the code

Read [the scorer Flow](evaluate_case.ex), then read the
[case fixture](fixtures/cases.json).

## Run it

`mix test.examples examples/22_application_evaluation/22_01_datasets_and_scorers --warnings-as-errors`

Expected result: the cited-answer and policy-refusal cases pass. A changed
answer fails exact-output and citation checks.

## Important behavior

The dataset is offline, versioned with the code, and repeatable. A single
Action is lowered to the same canonical execution model as a one-step Flow.
Each check remains visible instead of hiding behind one score.

## Limits

Exact matching does not measure semantic correctness, tone, or source support.
The aggregate score gives equal weight to all four checks.

## Core Fit and Gaps

Fixtures, Actions, Flows, and ExUnit provide enough integration coverage. Jido
does not need an Eval dataset or scorer API for this example.

## Files

- [Source](evaluate_case.ex)
- [Tests](evaluate_case_test.exs)
- [Cases](fixtures/cases.json)

[Next: Offline model judge](../22_02_offline_model_judge/README.md)
