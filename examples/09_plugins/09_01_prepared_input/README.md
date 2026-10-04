# 09_01 Prepared Input

An Agent Plugin reads the source Signal and returns one portable input under
its package key.

## What you will learn

- How `prepare/2` receives a read-only preparation value.
- How direct and live execution use the same pure preparation.
- How an Action reads `context.plugin_inputs[Package].prepared`.
- How preparation rejects input without changing the Signal.

## Read the code

Read [the Plugin and Agent](prepared_input.ex), then read the
[behavior tests](../../../test/examples/09_plugins/09_01_prepared_input/prepared_input_test.exs).

## Run it

```sh
mix test test/examples/09_plugins/09_01_prepared_input --include example --seed 0
```

Expected result: direct and live commands select the same tenant. They preserve
the Signal ID and subject. A missing tenant subject fails before route
execution.

## Important behavior

Preparation returns portable data under the Plugin package key. It cannot
change the source Signal or Agent state. Direct and live execution both use
this pure boundary.

## Limits

Prepared input is not live authorization. This example does not use private
runtime state or grant external authority.

## Files

- [Plugin and Agent](prepared_input.ex)
- [Tests](../../../test/examples/09_plugins/09_01_prepared_input/prepared_input_test.exs)

Previous: [Elastic Group](../../08_applications/08_08_elastic_group/README.md) | Next: [Runtime Admission](../09_02_runtime_admission/README.md)
