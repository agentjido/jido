# 10_07 Recoverable Delivery

An Agent saves business state and external delivery intent in one checkpoint.

## What you will learn

- How Plugin-owned state records pending and completed effect IDs.
- How a supervised worker resumes saved intent after restore.

## Read the code

Read [the Agent](recoverable_delivery.ex), then the [Plugin](delivery_plugin.ex), [worker](delivery_worker.ex), [sink contract](sink.ex), and [memory sink](support/memory_sink.ex).

## Run it

`mix test test/examples/10_persistence/10_07_recoverable_delivery --include example --seed 0`

Expected result: intent saved while the sink is unavailable resumes after restore and creates one idempotent external record.

## Important behavior

Delivery is at least once. The application owns stable effect IDs. The sink must accept a repeated ID and value as success.

## Limits

The memory sink is not durable. Completed IDs need an application retention policy.

## Files

- [Agent](recoverable_delivery.ex)
- [Plugin](delivery_plugin.ex)
- [Worker](delivery_worker.ex)
- [Sink](sink.ex)
- [Memory sink](support/memory_sink.ex)
- [Demo](demo.exs)
- [Tests](../../../test/examples/10_persistence/10_07_recoverable_delivery/recoverable_delivery_test.exs)

Previous: [Indeterminate Write](../10_06_indeterminate_write/README.md) | Next: [Definition Revision](../10_08_definition_revision/README.md)
