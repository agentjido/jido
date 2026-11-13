# 08_01 Signal Envelope

One custom Signal validates order data and builds a CloudEvents 1.0 envelope.

## What you will learn

- How `use Jido.Signal` fixes type, source, content type, and data schema.
- How a Signal keeps a UUID7 identity through JSON serialization.

## Read the code

Read [the Signal definition](signal_envelope.ex), then read
[the tests](signal_envelope_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_01_signal_envelope --warnings-as-errors`

Expected result: one order Signal round-trips without changing its identity or
data.

## Important behavior

The definition owns the Signal type and data schema. Constructor options
cannot replace them. JSON-bound Signal data uses string keys.

## Limits

Serialization does not deliver the Signal or authorize its source.

## Core Fit and Gaps

The custom Signal and codec compose when the data schema returns JSON values.
An atom-keyed Joi object returns an Elixir map that the JSON codec rejects.
The public catalog guide states the string-key rule, but it is easy to miss
when a developer moves from normal Action schemas to wire Signal schemas.

## Files

- [Signal](signal_envelope.ex)
- [Tests](signal_envelope_test.exs)
