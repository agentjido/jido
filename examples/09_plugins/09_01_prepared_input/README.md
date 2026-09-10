# 09_01 Prepared Input

An Agent Plugin reads the source Signal and returns one portable input under
its package key.

## What you will learn

- How `prepare/2` receives a read-only preparation value.
- How direct and live execution use the same pure preparation.
- How an Action reads `context.plugin_inputs[Package].prepared`.
- How preparation rejects input without changing the Signal.

## Run it

```sh
mix test test/examples/09_plugins/09_01_prepared_input --include example --seed 0
```

The successful commands preserve the Signal ID and subject. A missing tenant
subject fails before route execution.

Previous: [Elastic Group](../../08_applications/08_08_elastic_group/README.md) | Next: [Runtime Admission](../09_02_runtime_admission/README.md)
