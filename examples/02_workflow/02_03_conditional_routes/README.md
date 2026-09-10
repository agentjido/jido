# Conditional Routes

A Flow converts provider errors into explicit data and selects the first
matching Choice option.

## What you will learn

- How ordered Choice options apply first-match behavior.
- How expected provider failures can select a fallback.
- How an `otherwise` branch can reject unsupported failures.

## Read the code

Read [the Agent and Flow](conditional_routes.ex) first. Then read
[the behavior tests](../../../test/examples/02_workflow/02_03_conditional_routes/conditional_routes_test.exs).

## Run it

```sh
mix test test/examples/02_workflow/02_03_conditional_routes --include example --seed 0
```

Expected result: a successful primary response wins, an unavailable primary
uses the fallback, and a forbidden response fails.

## Important behavior

The fetch step decides which provider failures are normal data. Choice does not
turn Action errors into another branch. `Select` is named because four Choice
options reuse it.

## Limits

The provider policy is local example policy. It is not an automatic retry or
circuit-breaker feature.

## Files

- [Source](conditional_routes.ex)
- [Tests](../../../test/examples/02_workflow/02_03_conditional_routes/conditional_routes_test.exs)
- [Shared test adapter](../../../test/examples/support/workflow_sdk_case.ex)

Previous: [Effectful Steps](../02_02_effectful_steps/README.md) | Next: [Parallel Join](../02_04_parallel_join/README.md)
