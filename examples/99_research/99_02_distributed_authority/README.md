# 99_02 Distributed Authority

Status: retained research probe. Core contract `DIST-03` is not implemented.

Two local Erlang nodes use ownership tokens to fence Agent admission,
persistence writes, and external effects.

## Current public contract

Jido provides local Agent identity, shared persistence adapter hooks, live
Plugin admission, and exact-node placement. It does not provide a cluster owner
claim, lease, or leader election contract.

## Executable evidence

- A replacement owner can fence an older live Agent before its Action runs.
- Storage and effect boundaries reject stale tokens after disconnect and reconnect.

## Read the code

Read [the inventory Agent](fenced_inventory.ex), [the admission Plugin](gate.ex),
then [the controlled authority and adapters](support/authority.ex).

## Run it

```sh
mix test test/examples/99_research/99_02_distributed_authority --include example --seed 0
```

Expected result: only the latest token can admit work, persist state, or commit
an external effect on either peer node.

## Missing contract and workaround

`DIST-03` requires at most one live cluster owner for one logical Agent identity.
The example puts a monotonic token in an external authority and checks that token
at admission, persistence, and effect boundaries. This closes the test scenario
only when every application boundary uses the same authority.

The controlled authority is not a consensus service, lease provider, or durable
production store. The example does not prove availability during partitions,
automatic failover, or a Jido-owned cluster guarantee.

## Files

- [Agent](fenced_inventory.ex)
- [Admission Plugin](gate.ex)
- [Authority and adapters](support/authority.ex)
- [Core ownership probe](distributed_authority_probe.ex)
- [Tests](../../../test/examples/99_research/99_02_distributed_authority/fenced_inventory_test.exs)

Return to the [stable example catalog](../../README.md).
