# 09_05 Runtime ownership transfer

Adopt and transfer one resident Agent between local owner activations without
replacing the child process.

## What you will learn

- `Jido.transfer_agent_ownership/4` adopts an unowned resident Agent.
- The returned `Jido.AgentOwnership` value fences a later transfer.
- Only the current owner activation applies owner-linked shutdown.

## Read the code

Read [the ownership transfer client](ownership_ledger.ex) first.

## Run it

`mix test.examples examples/09_dynamic_agent_composition/09_05_logical_ownership_transfer --warnings-as-errors`

Expected result: ownership moves from `team-a` to `team-b`, while the worker
resolves to the same process. A stale transfer fails. Stopping `team-a` does
not stop the worker, but stopping `team-b` does.

## Important behavior

Adoption passes `expected: nil`. A transfer passes the exact current ownership
value. The fence contains the child activation identity and its ownership
generation. A matching `request_id` retry returns the same result. An accepted
Turn continues; transfer does not cancel or replay it. Work that already
captured runtime context keeps that context. A later Turn captures the new
owner.

The child monitors the owner activation root, not one owner worker PID. Worker
replacement keeps ownership. The operation releases the old owner link before
it returns success.

## Limits

Ownership is local and activation-scoped. It is not saved in Agent state or in
the persistence record. Child activation loss, passivation, or instance
shutdown releases it. Reactivation starts unowned. This example does not prove
distributed ownership, remote failover, or authorization.

## Core Fit and Gaps

Stable Addresses, `Jido.AgentOwnership`, and the public transfer operation
compose cleanly. The runtime keeps process ownership separate from durable
Agent state. A distributed or durable lease remains outside this contract.

## Files

- [Source](ownership_ledger.ex)
- [Tests](ownership_ledger_test.exs)

Previous: [Independent Agents](../09_04_independent_agents/README.md) | Next: [Shutdown behavior](../09_06_shutdown_behavior/README.md)
