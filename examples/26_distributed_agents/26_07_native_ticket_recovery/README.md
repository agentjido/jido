# 26_07 Recover a ticket with native OTP

Use B's Mnesia disk table to recover the same ticket and Turn after the home
moves from A to B.

## What you will learn

- Use the fixed-home options with synchronous Mnesia writes.
- Stop the old home, verify the fence, and change the home record.
- Recover an overdue deadline and read its retained terminal result.

## Read the code

Read the [ticket operations](example.ex) and the [ticket Flow](../support/ticket.ex).
The [peer tests](example_test.exs) provision a disk table on B and join A as a
RAM-only client.

## Run it

`mix test.examples examples/26_distributed_agents/26_07_native_ticket_recovery --warnings-as-errors`

The saved deadline increments the Agent revision once. The Address and Turn ID
stay the same. Acknowledgement clears the retained result.

## Important behavior

The tests confirm the old BEAM's exit before the move. A separate partition
keeps both peers alive and blocks promotion. The registered home must match
the canonical generation before the runtime can open the namespace.
The test controls the nodes through standard IO and removes their temporary data.

## Limits

The operator controls the move and restart fence. Loss of B or its disk stops
durable progress. Deadline recovery covers Jido state. Any external effect needs
its own delivery contract.

## Core Fit and Gaps

Jido owns Address routing, persistence, and Wake. Schema setup, the stop fence,
and the deployment procedure belong to the application operator. Automatic
takeover needs a separate [write authority](../../../docs/plans/2026-11-23-native-otp-clustering-plan.md#u4-prove-one-way-automatic-takeover).

## Files

- [Source](example.ex)
- [Tests](example_test.exs)
- [Mnesia test setup](support/mnesia_hosts.exs)
- [Ticket](../support/ticket.ex)

[Previous](../26_06_native_fixed_home/README.md)
