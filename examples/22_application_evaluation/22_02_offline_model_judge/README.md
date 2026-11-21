# 22_02 Offline model judge

This Flow sends one recorded application result and named questions to a
deterministic offline judge and records its exact input and output.

## What you will learn

- How a model judge remains an ordinary application Action.
- How to record judge model, input, questions, output, and digest.
- Why a judge result is evidence, not ground truth.

## Read the code

Read [the judge Action and Flow](offline_model_judge.ex) first.

## Run it

`mix test.examples examples/22_application_evaluation/22_02_offline_model_judge --warnings-as-errors`

Expected result: two identical runs produce the same judge output and input
digest without a network request.

## Important behavior

The example records the complete judge input and does not infer a pass from an
unstructured sentence. A production scorer must parse a declared judge output
contract and handle invalid output.

## Limits

The fixture counts questions. It does not assess answer quality or judge
agreement. Model judges can be biased, unstable, and sensitive to prompt form.

## Core Fit and Gaps

The inference-client evaluation callback and a normal Flow are sufficient. The
application owns judge prompts, output parsing, calibration, and stored
evidence. Jido core does not need an Eval runtime.

## Files

- [Source](offline_model_judge.ex)
- [Tests](offline_model_judge_test.exs)
- [Offline client](../../support/offline_inference_client.ex)

[Previous: Datasets and scorers](../22_01_datasets_and_scorers/README.md)

[Next: Trajectory and budgets](../22_03_trajectory_and_budgets/README.md)
