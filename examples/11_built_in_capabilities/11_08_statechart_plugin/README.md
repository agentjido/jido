# 11_08 Add a chart to an Agent

Use a chart to approve a release. Use a separate Agent route to record notes.

## What you will learn

- Add `Jido.Plugin.Statechart` to an Agent and route selected Signals to it.
- Bind an SCXML guard to a trusted Elixir function.
- Initialize the chart before sending review events.

## Read the code

Read [the Agent and its chart](example.ex), then [the behavior test](example_test.exs).

## Run it

```sh
mix test.examples examples/11_built_in_capabilities/11_08_statechart_plugin --warnings-as-errors
```

A failed review leaves the release in `review`. A note updates the Agent's
count. A successful review moves the release to `approved`.

## Important behavior

The guard accepts only a Signal that reports passing checks. The note route
does its work without taking a chart transition. The test stops the Agent
after approval.

## Limits

The example uses in-memory state. The caller supplies the result of the
release checks.

Previous: [Standalone approval chart](../11_07_statechart_approval/README.md).
