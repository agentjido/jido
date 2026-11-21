# 22_03 Tool trajectory and budgets

This one-step Flow checks exact tool order and arguments, guardrail outcome,
token use, cost, and latency against an offline run fixture.

## What you will learn

- How to test a tool trajectory, not only final text.
- How token, cost, and latency budgets produce separate checks.
- How offline regression fixtures preserve observed and expected values.

## Read the code

Read [the run checker](evaluate_run.ex), then read the
[run fixtures](fixtures/runs.json).

## Run it

`mix test.examples examples/22_application_evaluation/22_03_trajectory_and_budgets --warnings-as-errors`

Expected result: one run passes all checks. The regression run fails token,
cost, and latency checks while its tool and guardrail checks still pass.

## Important behavior

The checker uses exact tool order, names, arguments, and status. It reports
each budget separately. A single Action uses the same execution model as one
Flow, so the checker keeps normal validation and instrumentation.

## Limits

Fixture latency is recorded data, not a benchmark. Exact trajectory checks can
reject a different but valid tool plan. Cost data depends on provider reports.

## Core Fit and Gaps

Ordinary fixtures, Actions, and ExUnit assertions provide the required
application evaluation. Scale and latency claims require separate measured
benchmarks. Jido core does not need an Eval API for these checks.

## Files

- [Source](evaluate_run.ex)
- [Tests](evaluate_run_test.exs)
- [Run fixtures](fixtures/runs.json)

[Previous: Offline model judge](../22_02_offline_model_judge/README.md)
