# 09_05 Composition

One Agent combines a pure tenant input with a live authorization input.

## What you will learn

- How each Plugin owns one key in `plugin_inputs`.
- How pure preparation and live admission compose before route execution.
- How an Action explicitly selects the package inputs that it needs.
- How one rejection prevents all executable work.

## Run it

```sh
mix test test/examples/09_plugins/09_05_composition --include example --seed 0
```

The example does not use a shared mutable context. Each Plugin has one isolated
input value.

Previous: [Secure Signal](../09_04_secure_signal/README.md) | Next: [Progress Observation Research](../../99_research/99_01_progress_observation/README.md)
