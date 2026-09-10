# 99_10 Plugin Isolation

Status: implemented Plugin contract; candidate for stable Plugin guidance.

An Agent Action changes domain state while a Plugin alone controls its owned
state field.

## What this proves

- A successful Turn applies Plugin state reduction after Action execution.
- An Action cannot overwrite Plugin-owned state, and a failed Turn preserves it.

## Read the code

Read [the Agent and Plugin](plugin_isolation.ex).

## Run it

```sh
mix test test/examples/99_research/99_10_plugin_isolation --include example --seed 0
```

Expected result: the Plugin increments its field after valid work and the
pipeline rejects an Action candidate that changes that field.

## Gap and limits

The public contract exists. Promotion should add this boundary to the stable
Plugin learning path. Isolation is an API contract, not a sandbox for untrusted
BEAM code.

## Files

- [Source](plugin_isolation.ex)
- [Tests](../../../test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs)

Previous: [Route Selection](../99_09_route_selection/README.md) | Next: [Stable Reference](../99_11_stable_reference/README.md)
