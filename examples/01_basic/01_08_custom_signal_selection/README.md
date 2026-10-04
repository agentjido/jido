# 01_08 Custom Signal Selection

One Agent converts a raw Signal into a validated Turn and delegates normal
commands to its declared routes.

## What you will learn

- How to implement `handle_signal/2` and construct `Jido.Agent.Turn`.
- How to keep the unchanged source Signal bound to custom work.
- How explicit callback rejection stops selection without route fallback.

## Read the code

Read [the custom selector](custom_signal_selection.ex), then read its behavior
test.

## Run it

```sh
mix test test/examples/01_basic/01_08_custom_signal_selection --include example --seed 0
```

Expected result: raw string data becomes typed Action input, declared routes
still work, and explicit rejection does not commit state.

## Important behavior

The custom callback returns a Turn. Jido binds and validates the original
Signal before it runs the Action. Normal cases call `Jido.Agent.handle_signal/2`
to use declared routes. An explicit error does not try those routes.

## Limits

Use custom selection only when route data cannot express the input mapping.
Declared routes remain the simpler default.

## Files

- [Source](custom_signal_selection.ex)
- [Tests](../../../test/examples/01_basic/01_08_custom_signal_selection/custom_signal_selection_test.exs)

Previous: [Data-defined Agent](../01_07_data_defined_agent/README.md) | Next: [Workflow examples](../../02_workflow/README.md)
