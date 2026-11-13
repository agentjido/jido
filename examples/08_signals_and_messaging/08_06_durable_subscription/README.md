# 08_06 Durable Subscription

A durable subscriber loses its process before acknowledgement and receives the
same stored record after it attaches again.

## What you will learn

- How a stable durable subscription ID owns one cursor.
- How acknowledgement advances delivery and process loss causes repetition.

## Read the code

Read [the durable client](durable_subscription.ex), then read
[the failure drill](durable_subscription_test.exs).

## Run it

`mix test.examples examples/08_signals_and_messaging/08_06_durable_subscription --warnings-as-errors`

Expected result: the replacement subscriber receives the same cursor and then
acknowledges it.

## Important behavior

Delivery is ordered and at least once. The stable subscription ID, not the
subscriber PID, owns progress.

## Limits

The memory store does not survive Bus or BEAM loss. The Bus does not provide a
retry timer, dead-letter queue, lease, or competing-consumer policy.

## Core Fit and Gaps

Subscription identity, record cursor, process loss, repeated delivery, and
acknowledgement are public and directly testable. Cross-BEAM recovery needs an
application store that implements the Bus store contract.

## Files

- [Durable client](durable_subscription.ex)
- [Failure drill](durable_subscription_test.exs)

