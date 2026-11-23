# 26_05 Split the BEAM link with SQL still available

Run the ticket namespace on two nodes that share a SQL store. Cut the link
between the nodes while both can still reach the database.

## What you will learn

- Reproduce two live activations after the BEAM link drops.
- See why node connectivity and Agent ownership need separate decisions.

## Read the code

Read [the local ticket ingress](partitioned_ingress.ex), then read
[the partition test](partition_without_ownership_test.exs).

## Run it

`mix test.examples examples/26_distributed_agents/26_05_partition_without_ownership --warnings-as-errors`

Node A commits a note. With the BEAM link down, node B reads that note and
activates the same Address. Node A still commits a second note, which node B
can read from SQL. Both activations remain live when the link returns.

The default store is temporary SQLite. Use the
[PostgreSQL profile](../README.md#run-with-postgresql) to run the same test
against Postgres.

## Important behavior

The test blocks BEAM reconnection and leaves both SQL pools running.
Postgres or SQLite still gives both nodes access to the same record. Jido
controls activation through a Registry on each node. The test reconnects
the BEAM peers and stops both instances.

## Limits

This is a reproduction of the current ownership gap. The test commits
sequential updates and checks that both activations remain resident.

## Core Fit and Gaps

**Candidate Jido core change.** Repeat the split with an owner lease. While
node A can renew the lease, node B must reject local activation. Then stop A
from renewing, let B take over, and reconnect A. An A Turn that had already
started must fail its commit check once B holds a newer lease. Any pending
deadline must resolve under the valid lease.

## Files

- [Local ticket ingress](partitioned_ingress.ex)
- [Ticket Agent](../support/ticket.ex)
- [Tests](partition_without_ownership_test.exs)
- [SQL test setup](../support/sql_hosts.exs)

[Previous lesson](../26_04_recover_a_ticket_deadline/README.md) · [Next core contracts](../README.md#next-core-contracts)

[Next](../26_06_native_fixed_home/README.md)
