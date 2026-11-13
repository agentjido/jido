# 01_04 Effects as Data

One Action prepares an email request and returns delivery intent as data.

## What you will learn

- How an Action returns ordered effect requests with normal output.
- Why `Jido.Exec` carries effects but does not dispatch them.

## Read the code

Read [the Action](effects_as_data.ex), then read
[the tests](effects_as_data_test.exs).

## Run it

`mix test.examples examples/01_actions/01_04_effects_as_data --warnings-as-errors`

Expected result: the caller receives one prepared result and one email effect
request. No email is sent.

## Important behavior

Effects are ordered data. A later host decides when and how to run them.

## Limits

This lesson does not provide delivery, retry, idempotency, or compensation.

## Files

- [Action](effects_as_data.ex)
- [Tests](effects_as_data_test.exs)

