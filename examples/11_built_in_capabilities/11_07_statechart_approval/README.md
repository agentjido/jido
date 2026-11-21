# 11_07 Standalone approval chart

Start one Agent per order and choose a final decision with a Signal.

## What you will learn

- Use the `~SCXML` sigil to compile a chart.
- Start an initialized Agent with `Jido.Statechart.spawn/3`.
- Read the committed session with `Jido.Statechart.session/1`.

## Read the code

Read [the approval chart](example.ex), then [the behavior test](example_test.exs).

## Run it

```sh
mix test.examples examples/11_built_in_capabilities/11_07_statechart_approval --warnings-as-errors
```

Each order starts in `pending` and reaches either `approved` or `rejected`.

## Important behavior

A completed chart keeps its decision when it receives another Signal. The
test stops each Agent after checking its decision.

## Limits

This example uses an in-memory Agent and two application events.

Next: [Add a chart to an Agent](../11_08_statechart_plugin/README.md).
