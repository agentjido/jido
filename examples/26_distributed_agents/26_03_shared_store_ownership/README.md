# 26_03 Shared storage and Agent ownership

Start two Jido instances with the same namespace and Mnesia table. Both can
restore the same Agent Address at the same time.

## What you will learn

- Use a shared store to read committed Agent state on another BEAM.
- Reproduce the gap between local registration and cluster-wide ownership.

## Read the code

Read [the activation request](shared_store_ownership.ex) and
[the two-host test](shared_store_ownership_test.exs).

## Run it

`mix test.examples examples/26_distributed_agents/26_03_shared_store_ownership --warnings-as-errors`

Node A commits a count of 1. Node B initially resolves no local worker. It
then activates the same Address and reads the count of 1. Each node can
resolve its own live worker for that Address. The test passes when it
reproduces both activations.

## Important behavior

Mnesia provides the canonical saved record. Each Jido instance separately
controls local activation. The second host reads the first host's committed
state and starts another worker. The test shuts down both instances and
stops Mnesia on both peers.

## Limits

This reproduction exercises activation and one committed update. Use the
pinned host pattern for a deployed singleton.

## Core Fit and Gaps

**Candidate Jido core change.** A shared store provides state and atomic writes.
An owner decision must also cover activation. To turn the reproduction into a
singleton acceptance test, make both hosts eligible and race calls for the
same Address. Verify one activation and both committed Turns. If the
application can change owners while the old owner is still alive, require
that authority at commit and wake delivery as well.

## Files

- [Activation request](shared_store_ownership.ex)
- [Tests](shared_store_ownership_test.exs)
- [Counter Agent](../support/counter.ex)

[Previous lesson](../26_02_move_a_durable_agent/README.md) · [Next lesson](../26_04_recover_a_ticket_deadline/README.md)
