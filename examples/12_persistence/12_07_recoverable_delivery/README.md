# 12_07 Recoverable Delivery

An Agent saves business state and external delivery intent in one checkpoint.

## What you will learn

- How Plugin-owned state records pending and completed effect IDs.
- How a supervised worker resumes saved intent after restore.

## Read the code

Read the shared [Agent](../../support/recoverable_delivery/recoverable_delivery.ex),
then the [Plugin](../../support/recoverable_delivery/delivery_plugin.ex),
[worker](../../support/recoverable_delivery/delivery_worker.ex),
[sink contract](../../support/recoverable_delivery/sink.ex), and
[memory sink](../../support/recoverable_delivery/memory_sink.ex).

## Run it

```sh
mix test.examples examples/12_persistence/12_07_recoverable_delivery --warnings-as-errors
mix run examples/12_persistence/12_07_recoverable_delivery/demo.exs
```

Expected result: intent saved while the sink is unavailable resumes after restore and creates one idempotent external record.

## Important behavior

Delivery is at least once. The application owns stable effect IDs. The sink must accept a repeated ID and value as success.

## Limits

The memory sink is not durable. Completed IDs need an application retention policy.

## Core Fit and Gaps

Public Agent Addresses, persistence, Plugin-owned state, runtime children, and
post-commit dispatch compose into a recoverable delivery protocol. The
application still owns stable effect IDs and idempotent external delivery. No
distributed transaction spans the Agent record and the sink.

## Files

- [Shared Agent](../../support/recoverable_delivery/recoverable_delivery.ex)
- [Shared Plugin](../../support/recoverable_delivery/delivery_plugin.ex)
- [Shared Worker](../../support/recoverable_delivery/delivery_worker.ex)
- [Shared sink contract](../../support/recoverable_delivery/sink.ex)
- [Shared memory sink](../../support/recoverable_delivery/memory_sink.ex)
- [Demo](demo.exs)
- [Tests](recoverable_delivery_test.exs)

Previous: [Indeterminate Write](../12_06_indeterminate_write/README.md) | Next: [Definition Revision](../12_08_definition_revision/README.md)
