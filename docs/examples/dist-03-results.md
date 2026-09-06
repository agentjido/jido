> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# DIST-03: stable identity and recovery authority

Date: **2026-09-04**. Status: **Paused at cluster ownership authority**.

The new probe uses two Erlang nodes and one shared compare-and-swap checkpoint
store. It does not simulate Agent commits. Both nodes run real Jido instances,
and both Agent Servers use the normal persistence boundary.

## What works

An Agent on node A commits revision 1. A second activation with the same Agent
ID starts on node B and restores revision 1. After the second activation commits
revision 2, the older activation cannot commit. Its expected revision is stale,
so the shared atomic compare-and-swap returns a conflict. The stored result stays
at revision 2.

This proves stable checkpoint identity across node replacement and stale-write
rejection after the replacement advances the revision. It uses the same Agent
module, Jido instance name, partition, Agent ID, and persistence record key on
both nodes.

## First unsupported boundary

Starting the second activation while the first is live also succeeds. Jido's
Registry and DynamicSupervisor are local to each node. The checkpoint revision
is a write fence, not a cluster ownership claim. Before either activation
commits a later revision, both can perform external work and both believe that
they own the same logical Agent ID.

The enabled test **“one logical identity has at most one live cluster owner”**
expects the second start to return the existing owner. Current Jido returns a
second PID on node B. This is the first failing DIST-03 acceptance boundary.

The focused DIST-03 run reports **one passing test and one enabled failure, no
skips**. The passing test proves restore and stale revision fencing. The failure
is the exact cluster-owner assertion above.

The wider focused distribution run reports **21 of 22 passing, one failure, no
skips**. All 20 DIST-01 and DIST-02 tests pass. The sole failure is the new
DIST-03 cluster-owner assertion.

```shell
mix test test/jido/agent/distributed_authority_test.exs --seed 0
```

The [Agent probe](../../examples/99_research/99_02_distributed_authority/distributed_authority_probe.ex)
uses the normal Spark Agent DSL and a typed command. The test adapter forwards
the existing `Jido.Persistence.ETS` compare-and-swap operations to node A. It is
an authoritative test store for the two live VMs; it is not a durable database
or a lease implementation.

## Design decision needed

I recommend amending DIST-03 instead of adding a distributed lock to Agent
Server. OTP supervisors and registries own processes on one node. They do not
provide a safe cluster singleton during a network partition. A production
owner claim needs an external consensus or lease authority with expiry,
fencing tokens, and an explicit partition policy.

Under the smaller core contract:

1. Jido keeps Agent registry and supervision node-local.
2. A placement or recovery service claims a logical Agent before startup.
3. That authority gives the activation a monotonically increasing fencing token.
4. Persistent writes and externally visible effects validate that token.
5. Agent ID, partition, activation ID, and checkpoint revision remain separate
   identities.
6. Manual replacement without a lease is supported but does not claim exclusive
   cluster ownership.

The alternative is a new core ownership provider behavior. Agent startup would
require `claim`, `renew`, and `release` operations and would stop or isolate an
activation after loss of authority. That is a larger failure-detection and
partition-policy contract. A node monitor or `:global` registration alone is
not sufficient because neither gives a fencing token to storage and external
systems.

Further DIST-03 work is paused for this decision. No ownership implementation
was added to core. `mix quality` and `mix docs --no-open` pass after the probe.
