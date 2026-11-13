# 09_05 Logical ownership transfer

Adopt and transfer an independent Agent in application-owned domain state
without pretending that its OTP process moved.

## What you will learn

- A durable ownership ledger can name the logical owner of a stable Agent Address.
- Transfer validates the current owner before it commits the new owner.
- The Jido instance remains the process owner before and after transfer.

## Read the code

Read [the ownership ledger Agent](ownership_ledger.ex) first.

## Run it

`mix test.examples examples/09_dynamic_agent_composition/09_05_logical_ownership_transfer --warnings-as-errors`

Expected result: ownership moves from `team-a` to `team-b`, while the worker
resolves to the same process. A stale transfer fails without an Agent-state
revision.

## Important behavior

The ledger is the canonical owner of logical ownership data. AgentServer owns
the ledger process. The Jido instance owns the worker activation. A transfer is
one ledger commit; it does not move or restart the worker process.

## Limits

Jido core does not currently expose public dynamic child adoption or process
ownership transfer. This example does not claim that application ownership
data changes OTP supervision.

## Core Fit and Gaps

Stable Addresses and normal Agent state provide a clean application-level ownership
protocol. Runtime adoption, transfer, and owner-linked shutdown need a separate
public contract if Jido intends to support them.

## Files

- [Source](ownership_ledger.ex)
- [Tests](ownership_ledger_test.exs)

Previous: [Independent Agents](../09_04_independent_agents/README.md) | Next: [Shutdown behavior](../09_06_shutdown_behavior/README.md)
