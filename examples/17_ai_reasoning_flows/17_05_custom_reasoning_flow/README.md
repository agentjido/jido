# 17_05 Custom reasoning Flow

Use a normal Flow schema to define and override application reasoning input.

## What you will learn

- How a custom reasoning Flow owns defaults and validation.
- How Agent defaults and request input resolve through one Flow schema.

## Read the code

Read [the reasoning Flow and Agent](schema_driven_overrides.ex), then read the
behavior test.

## Run it

```sh
mix test.examples examples/17_ai_reasoning_flows/17_05_custom_reasoning_flow --warnings-as-errors
```

Expected result: Agent defaults apply, request values replace them, and unknown
input is rejected.

## Important behavior

The Flow produces a deterministic response. It does not call a model provider.

## Limits

The example does not compare model reasoning quality or select a strategy at
run time.

## Core Fit and Gaps

The public Flow schema and AI Agent reasoning declaration compose cleanly. No
private API or provider fixture is required. This example does not identify a
core SDK gap.

## Files

- [Source](schema_driven_overrides.ex)
- [Tests](schema_driven_overrides_test.exs)

Previous: [ReAct tool loop](../17_01_react_tool_loop/README.md)
