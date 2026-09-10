# 09_02 Runtime Admission

An Agent Server Plugin uses private runtime state to add one transient
authorization input.

## What you will learn

- Why private runtime work belongs in `admit/3`, not pure `prepare/2`.
- How admission reads a fixed value and returns only its package runtime input.
- Why a live package input can contain a PID, reference, or function.
- Why direct `cmd/3` cannot use this live-only capability.

## Run it

```sh
mix test test/examples/09_plugins/09_02_runtime_admission --include example --seed 0
```

The authorization contains a transient lease reference. The Action consumes
`context.plugin_inputs[Package].runtime` but does not copy the reference into
Agent state.

Previous: [Prepared Input](../09_01_prepared_input/README.md) | Next: [Identity](../09_03_identity/README.md)
