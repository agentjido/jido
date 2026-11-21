# 15_06 Request contract

Use `preflight/1` to validate input and compile the root Flow without model or
tool work. It reports the normalized request, declared tools, and workflow.
The request tool policy selects what the model can use at run time.

## What you will learn

- How preflight validates and compiles without model work.
- Which request, run, usage, and Session fields remain visible.

## Read the code

Read [the Agent](agent.ex), then [the tests](request_contract_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_06_request_contract --warnings-as-errors
```

Expected result: preflight exposes normalized limits, tools, and workflow; the
offline run records ordered Session entries.

## Important behavior

Tool policy selects from declared tools. It does not register new targets.

## Limits

Preflight validates and compiles the request. It does not reserve provider
capacity, authorize a user, or predict model output quality.

## Files

- [Agent](agent.ex)
- [Tests](request_contract_test.exs)

Previous: [Streaming](../15_05_streaming/README.md) | Next: [Core composition](../15_07_core_composition/README.md)
