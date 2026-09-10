# FA-02: Plugin-owned state isolation

Status: **Core feature available**.

Result on 2026-09-09: 2 passing checks. No check is skipped.

## Feature and proof

Owned Plugin state updates successfully. An Action cannot overwrite it, and a
failed live Turn preserves the committed state.

## Implemented contract

An Action or Flow proposes domain state. After success, the Plugin updates only
its owned field. The pipeline rejects an executable that changes that field.

## Scope

The example uses one domain field and one Plugin-owned field in the same Agent
state map. Callback isolation is an API contract, not a sandbox for untrusted
BEAM code.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_10_plugin_isolation --include example --seed 0
```

This command must pass with no skipped check.

[Source](../../../../examples/99_research/99_10_plugin_isolation/plugin_isolation.ex) · [Tests](plugin_isolation_test.exs)
