# 12_06 Indeterminate Write

An uncertain persistence result blocks work on stale live state and suppresses
an unconfirmed Directive.

## What you will learn

- How Jido treats a lost write reply as an indeterminate result.
- Why the old activation becomes faulted until the application reconciles or
  stops it.

## Read the code

Read [the Agent](indeterminate_write_probe.ex), then the deterministic
[fault adapter](indeterminate_store.ex), and then the behavior test.

## Run it

`mix test.examples examples/12_persistence/12_06_indeterminate_write --warnings-as-errors`

Expected result: storage contains the candidate revision, no output Signal is
sent, and the activation remains registered but blocks another command until
the application reconciles it. Reconciliation replaces the process from the
authoritative record, after which normal stop succeeds.

## Important behavior

Stored bytes do not prove that the live command committed. Recovery must read
the authoritative record before work continues. A direct stop is rejected as
`unsafe_resume`. The test reconciles through the stable Agent Address, then stops
the replacement and proves process cleanup.

## Limits

The example does not prescribe automatic restart, a shutdown reason, or cross-node ownership.

## Core Fit and Gaps

The public store behavior, uncertain `TurnResult`, operational status, and
stable Address recovery operations expose the boundary without private runtime
access. An application must reconcile before it can stop this activation
safely. Jido does not guess whether an indeterminate remote write won.

## Files

- [Source](indeterminate_write_probe.ex)
- [Fault adapter](indeterminate_store.ex)
- [Tests](indeterminate_write_test.exs)

Previous: [Durable Delete](../12_05_durable_delete/README.md) | Next: [Recoverable Delivery](../12_07_recoverable_delivery/README.md)
