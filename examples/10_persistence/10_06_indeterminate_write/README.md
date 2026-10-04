# 10_06 Indeterminate Write

An uncertain persistence result stops work on stale live state and blocks an unconfirmed Directive.

## What you will learn

- How Jido treats a lost write reply as an indeterminate result.
- Why the old activation must stop before it accepts more work.

## Read the code

Read [the Agent](indeterminate_write_probe.ex), then read its behavior test and the test-only fault adapter.

## Run it

`mix test test/examples/10_persistence/10_06_indeterminate_write --include example --seed 0`

Expected result: storage contains the candidate revision, no output Signal is sent, and the old process cannot run another command.

## Important behavior

Stored bytes do not prove that the live Turn committed. Recovery must read the authoritative record before work continues.

## Limits

The example does not prescribe automatic restart, a shutdown reason, or cross-node ownership.

## Files

- [Source](indeterminate_write_probe.ex)
- [Tests](../../../test/examples/10_persistence/10_06_indeterminate_write/indeterminate_write_test.exs)
- [Fault adapter](../../../test/support/persistence/fixtures/probe_store.ex)

Previous: [Durable Delete](../10_05_durable_delete/README.md) | Next: [Recoverable Delivery](../10_07_recoverable_delivery/README.md)
