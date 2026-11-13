# 08_02 Signal Schema and Context

One request keeps validated domain data separate from flat tenant transport
context.

## What you will learn

- How a custom Signal validates domain data.
- How `Jido.Signal.Context` validates CloudEvents extension attributes.

## Read the code

Read [the Signal](signal_schema_and_context.ex), then read
[the tests](signal_schema_and_context_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_02_signal_schema_and_context --warnings-as-errors`

Expected result: valid data and `tenantid` remain separate; invalid data and
invalid context names fail.

## Important behavior

Context is flat transport metadata. Domain values stay in Signal data.

## Limits

A tenant context value is not proof of authorization.

## Files

- [Signal](signal_schema_and_context.ex)
- [Tests](signal_schema_and_context_test.exs)

