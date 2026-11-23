# 26_02 Move a durable Agent

Move an approval desk from one BEAM to another while the desk waits for a
decision. Keep the Agent Address, committed state, and waiting Turn.

## What you will learn

- Shut down the old instance before the new instance opens the namespace.
- Restore committed state and continue a waiting Turn through the same Address.

## Read the code

Read [the approval Agent and Flow](approval_desk.ex), then read
[the order of the move](move_a_durable_agent_test.exs).

## Run it

`mix test.examples examples/26_distributed_agents/26_02_move_a_durable_agent --warnings-as-errors`

The old host commits request 1 and waits on request 2. The new host opens
revision 1, receives the approval Signal, and commits revision 2. Request 2
keeps its Turn ID and the new process has a new activation ID.
The approval history contains both requests.

## Important behavior

The operator stops the old instance and confirms that its process exited.
The operator starts the new instance with the same namespace and store and
sends the approval to the new host. The persisted Agent and waiting Turn are
authoritative. The new AgentServer restores them on the first call. The test
stops the new instance after it verifies the commit.

## Limits

The two peers share a local directory. The file store is used by one host at
a time. The move uses a planned shutdown and a matching Signal to resolve
the wait. Timed wakes under competing hosts need their own acceptance case.

## Core Fit and Gaps

**Application code.** The operator orders the stop, start, and route update.
Jido already restores the Agent and its waiting Turn. A planned move can use
these operations with the store that the application deploys.

## Files

- [Approval Agent and Flow](approval_desk.ex)
- [Tests](move_a_durable_agent_test.exs)

[Previous lesson](../26_01_pinned_singleton/README.md) · [Next lesson](../26_03_shared_store_ownership/README.md)
