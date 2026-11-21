# 02_05 Authoring Equivalence

DSL, direct data, and trusted JSON produce the same canonical Flow.

## What you will learn

- How different authoring forms converge on one value model.
- How semantic Flow identity stays equal across those forms.

## Read the code

Read [the comparison](authoring_equivalence.ex), then
[the test](authoring_equivalence_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_05_authoring_equivalence --warnings-as-errors`

Expected result: all three definitions and semantic identities are equal.

## Important behavior

Parity applies when every stored reference resolves to the same trusted
target.

## Limits

The example does not compare runtime services or code-only callbacks.

## Files

- [Comparison](authoring_equivalence.ex)
- [Tests](authoring_equivalence_test.exs)

[Previous: Stored JSON](../02_04_stored_json/README.md) |
[Next: Validation](../02_06_validation/README.md)
