# 99_02 Distributed Authority

Status: application extension with an explicit external authority.

Two local Erlang nodes use ownership tokens to fence Agent admission,
persistence writes, and external effects.

## What this proves

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

## Gap and limits

Jido does not provide cluster-wide exclusive ownership. The controlled authority
is not a consensus service, lease provider, or durable production store.

## Files

- [Agent](fenced_inventory.ex)
- [Admission Plugin](gate.ex)
- [Authority and adapters](support/authority.ex)
- [Core ownership probe](distributed_authority_probe.ex)
- [Tests](../../../test/examples/99_research/99_02_distributed_authority/fenced_inventory_test.exs)

Previous: [Progress Observation](../99_01_progress_observation/README.md) | Next: [Input Resource Lifecycle](../99_03_input_resource_lifecycle/README.md)
