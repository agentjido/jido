# 03_19 Choice and Fallback

A Flow converts provider errors into explicit data and selects the first
matching Choice option.

## What you will learn

- How ordered Choice options apply first-match behavior.
- How expected provider failures can select a fallback.
- How an `otherwise` branch can reject unsupported failures.

## Read the code

Read [the Agent and Flow](conditional_routes.ex) first. Then read
[the behavior tests](conditional_routes_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_19_conditional_routes
```

Expected result: a successful primary response wins, an unavailable primary
uses the fallback, and a forbidden response fails.

## Important behavior

The fetch step decides which provider failures are normal data. Choice does not
turn Action errors into another branch. `Select` is named because four Choice
options reuse it.

Choice conditions are `Jido.Expr` values. They describe portable comparisons;
they are not anonymous predicate functions.

## Limits

The provider policy is local example policy. It is not an automatic retry or
circuit-breaker feature.

## Files

- [Source](conditional_routes.ex)
- [Tests](conditional_routes_test.exs)
Previous: [Effectful Steps](../03_18_effectful_steps/README.md) | Next: [Parallel Join](../03_20_parallel_join/README.md)
