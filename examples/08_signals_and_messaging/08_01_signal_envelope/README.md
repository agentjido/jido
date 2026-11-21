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
The [Signal data schema guide](../../../guides/signals/signal-data-schemas.md#use-string-keys-for-json-data)
shows the failing atom-key form beside the correct string-key form. Action
schemas commonly use atom keys, but a Signal that crosses a JSON boundary must
use string keys and JSON values.

## Files

- [Signal](signal_envelope.ex)
- [Tests](signal_envelope_test.exs)
