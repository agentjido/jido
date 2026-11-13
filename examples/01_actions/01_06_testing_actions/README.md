# 01_06 Testing Actions

One table-driven test checks Action success and boundary failure through the
same public execution path used by applications.

## What you will learn

- How to test representative values and boundary values.
- Why a behavior test uses `Jido.Exec` instead of calling `run/2` directly.

## Read the code

Read [the Action](testing_actions.ex), then read
[the tests](testing_actions_test.exs).

## Run it

`mix test.examples examples/01_actions/01_06_testing_actions --warnings-as-errors`

Expected result: discounts of 0, 25, and 100 percent pass; 101 percent fails
input validation.

## Important behavior

The test covers validation, Action execution, output validation, and error
normalization as one public contract.

## Limits

Three cases do not prove all integer behavior. Property tests are a separate
repository gate.

## Files

- [Action](testing_actions.ex)
- [Tests](testing_actions_test.exs)
