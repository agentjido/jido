# 26_04 Recover a ticket deadline after a crash

A support ticket waits for approval when its host crashes. Start the
namespace on the surviving BEAM and let Jido recover the deadline from SQL.

## What you will learn

- Retain a Turn result so another Machine can read it by Address and Turn ID.
- Recover a durable deadline after abrupt BEAM loss.
- Identify the operator step that automatic takeover must replace.

## Read the code

Start with [the Ticket Agent and deadline Flow](../support/ticket.ex). Then
read [the result lookup](result_lookup.ex) and [the crash test](ticket_deadline_test.exs).

## Run it

`mix test.examples examples/26_distributed_agents/26_04_recover_a_ticket_deadline --warnings-as-errors`

The test opens a five-second approval wait and kills the host before the
deadline. The survivor restores the same Address and Turn ID under a new
activation. The deadline commits an escalation at Agent revision 1. The
test also approves a second ticket in time and checks its approved state.

The default store is temporary SQLite. Use the
[PostgreSQL profile](../README.md#run-with-postgresql) to run the same test
against Postgres.

## Important behavior

The two peers each have a connection to the same SQL database. The test
confirms the old BEAM has exited before it starts the namespace on the
survivor. The test reads the terminal result by ID and acknowledges it. Jido's
normal wake recovery runs the timer without a new request or a replay of the
original Signal.

## Limits

The test explicitly starts the survivor after host loss. The Agent records
the escalation in state. An external ticket system needs its own
[idempotent delivery boundary](../../24_application_patterns/24_07_recoverable_external_delivery/README.md).

## Core Fit and Gaps

**Application code.** The approval Flow uses a stable Address and accepts a
matching Signal. The store persists the waiting Turn and its deadline.

**Candidate Jido core change.** Replace the explicit survivor start with an
ownership grant. Run the same assertions with both hosts eligible from the
start. After a hard kill, the survivor must acquire the namespace, restore the
deadline, and commit the same Turn once.

## Files

- [Ticket Agent and Flow](../support/ticket.ex)
- [Result lookup](result_lookup.ex)
- [Tests](ticket_deadline_test.exs)
- [SQL test setup](../support/sql_hosts.exs)

[Previous lesson](../26_03_shared_store_ownership/README.md) · [Next lesson](../26_05_partition_without_ownership/README.md)
