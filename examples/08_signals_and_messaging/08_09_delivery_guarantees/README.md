# 08_09 Delivery guarantees and limits

Compare the acceptance, retention, acknowledgement, retry, and duplicate
boundaries of the Chapter 8 delivery paths.

## What you will learn

- Agent calls return one accepted Turn result but do not retry it.
- PID and PubSub dispatch do not retain a replay log.
- Bus publication returns a recorded cursor, and a durable subscription uses
  explicit acknowledgement for replay progress.
- No path removes the need for domain idempotency.

## Read the code

Read [the explicit contract table](delivery_guarantees.ex) after Lessons 4
through 8.

## Run it

`mix test.examples examples/08_signals_and_messaging/08_09_delivery_guarantees --warnings-as-errors`

Expected result: every supported path names its acceptance, acknowledgement,
retry, and duplicate boundary. Only recorded Bus paths claim replay retention.

## Important behavior

An adapter returning `:ok` means that the adapter accepted its local delivery
operation. It is not a universal remote acknowledgement. A caller timeout does
not prove that an accepted Agent Turn stopped. A durable Bus subscription can
repeat an unacknowledged record.

## Limits

The comparison does not claim exactly-once delivery, network durability,
cross-node fencing, or transactional state-and-message commit.

## Core Fit and Gaps

The public APIs expose distinct acceptance and acknowledgement values. They do
not combine them into one misleading delivery level. Application code must
select a path and idempotency rule that match its failure model.

## Files

- [Contract table](delivery_guarantees.ex)
- [Tests](delivery_guarantees_test.exs)

Previous: [Follow One Signal](../08_08_follow_one_signal/README.md)

