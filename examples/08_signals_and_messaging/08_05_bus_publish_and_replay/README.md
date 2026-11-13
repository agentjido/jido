# 08_05 Bus Publish and Replay

One local Signal Bus stores two records before ordered subscription delivery
and later replay.

## What you will learn

- How to subscribe by Signal type path.
- How publication returns stored cursors that replay can read.

## Read the code

Read [the Bus client](bus_publish_and_replay.ex), then read
[the tests](bus_publish_and_replay_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_05_bus_publish_and_replay --warnings-as-errors`

Expected result: the subscriber and replay both see values 1 and 2 in order.

## Important behavior

The Bus stores each record before it sends the subscriber message.

## Limits

The included memory store does not survive a Bus or BEAM restart.

## Core Fit and Gaps

Publish, subscription delivery, and replay use one public Bus contract. A
durable external store is an application adapter concern.

## Files

- [Bus client](bus_publish_and_replay.ex)
- [Tests](bus_publish_and_replay_test.exs)
