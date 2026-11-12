# 11_05 Composition

One Agent combines a pure tenant input with a live authorization input.

## What you will learn

- How each Plugin owns separate `prepared` and `runtime` input slots.
- How pure preparation and live admission compose before route execution.
- How an Action explicitly selects the package inputs that it needs.
- How one rejection prevents all executable work.

## Read the code

Read [the composed Agent](composition.ex), then read the
[behavior tests](composition_test.exs).
Read [the local input Plugins](inputs.ex) next. These small local copies keep
both inputs visible in this lesson. Their contracts match the earlier lessons.

## Run it

```sh
mix test.examples examples/11_plugins/11_05_composition
```

Expected result: a valid tenant and live token commit one owner value. A
rejection from either Plugin prevents route execution and state change.

## Important behavior

The example does not use a shared mutable context. Each Plugin has one isolated
input record with a pure slot and a live slot. The Action names each package
whose data it consumes.

## Limits

This example composes two inputs only. It does not define a general policy
language or allow one Plugin to change another Plugin's input.

## Files

- [Composed Agent](composition.ex)
- [Tests](composition_test.exs)

Previous: [Plugin DSL](../11_04_plugin_dsl/README.md) | Next: [Live Plugin Changes](../11_06_live_plugin_changes/README.md)
