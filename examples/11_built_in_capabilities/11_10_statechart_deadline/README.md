# 11_10 Cancel a Statechart deadline

Hold stock for checkout. The reservation expires at its deadline unless checkout
confirms it first.

## What you will learn

- How an SCXML state schedules an event with `send` and an ID.
- How a transition uses `cancel` with the same ID to remove the pending send.

## Read the code

Read [the reservation chart](reservation.ex), then
[compare the two live Agents](reservation_test.exs).

## Run it

`mix test.examples examples/11_built_in_capabilities/11_10_statechart_deadline --warnings-as-errors`

The unconfirmed hold expires. The confirmed hold stays active and receives no
deadline Turn. The test stops both Agents.

## Important behavior

Entering `held` schedules the deadline after commit. Exiting through
`examples.reservation.confirm` cancels that exact scheduled send. The
`confirmed` state stays active so chart completion cannot cancel the send on
its behalf. The test observes a second hold with the same delay and waits for
its expiry as a reference.

## Limits

The deadline lasts for the life of the chart runtime. If it arrives before
confirmation, the reservation expires.

## Core Fit and Gaps

The chart defines the timer effect and its cancellation at the transition
that owns the reservation. Tests observe the delivered Signal through public
Turn telemetry. The Statechart timer has no public controllable clock, so the
test uses one short real deadline.

## Files

- [Chart](reservation.ex)
- [Tests](reservation_test.exs)

Previous lesson [Behavior Tree continuation](../11_09_behavior_tree/README.md)

Next lesson [Share an inventory count](../11_11_shared_blackboard/README.md)
