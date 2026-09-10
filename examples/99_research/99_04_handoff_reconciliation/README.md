# 99_04 Handoff Reconciliation

Status: application protocol; not a Jido handoff API.

A coordinator transfers one request only after the new worker acknowledges its
ownership generation.

## What this proves

- The old owner remains authoritative until acknowledgement.
- Stale results, duplicate results, and a failed recipient do not replace ownership.

## Read the code

Read [the coordinator](handoff.ex), then [the worker](worker.ex).

## Run it

```sh
mix test test/examples/99_research/99_04_handoff_reconciliation --include example --seed 0
```

Expected result: transfer commits after acknowledgement, a recipient crash
clears the offer, and explicit reconciliation starts a new generation.

## Gap and limits

The protocol supports one request and one live coordinator. It does not restore
a durable coordinator, solve network partitions, or fence external effects.

## Files

- [Coordinator](handoff.ex)
- [Worker](worker.ex)
- [Tests](../../../test/examples/99_research/99_04_handoff_reconciliation/handoff_test.exs)

Previous: [Input Resource Lifecycle](../99_03_input_resource_lifecycle/README.md) | Next: [Shared Budget](../99_05_capacity_deadlines_cleanup/README.md)
