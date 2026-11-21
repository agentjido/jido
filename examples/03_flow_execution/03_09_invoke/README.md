# 03_09 Invoke

Invoke validates a decision, then selects one Action or Flow at run time.

## What you will learn

- How a decision and expander choose a trusted target.
- How dynamic work stays behind one Invoke node.

## Read the code

Read [the Invoke Flow](invoke.ex), then [the test](invoke_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_09_invoke --warnings-as-errors`

Expected result: each valid decision runs its selected target, while an invalid
decision fails before target work starts.

## Important behavior

The dynamic target does not change the parent Runic graph.

## Limits

Invoke does not accept arbitrary modules or unvalidated plans.

## Files

- [Invoke Flow](invoke.ex)
- [Tests](invoke_test.exs)

[Previous: Subflow](../03_08_subflow/README.md) |
[Next: Handoff](../03_10_handoff/README.md)
