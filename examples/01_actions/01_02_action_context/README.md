# 01_02 Action Context

One quote Action reads runtime tax policy from context without adding it to
portable request input.

## What you will learn

- How Action input carries requested work.
- How execution context carries runtime services and policy.

## Read the code

Read [the Action](action_context.ex), then read
[the tests](action_context_test.exs).

## Run it

`mix test.examples examples/01_actions/01_02_action_context --warnings-as-errors`

Expected result: a 7.25 percent policy produces a total of `10_725` cents.

## Important behavior

Missing runtime policy returns a structured error. The Action does not use a
global configuration value.

## Limits

Context is caller-owned and is not portable or persisted by this lesson.

## Files

- [Action](action_context.ex)
- [Tests](action_context_test.exs)
