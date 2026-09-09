# FA-02: Plugin read and prepared-input isolation

Status: **Core feature available**.

Result on 2026-09-09: **4 passing checks.** All checks are enabled.

## Feature and proof

Owned Plugin state updates successfully. An Action cannot overwrite it, and
failure preserves live state. The audit callback receives only its declared
`total` field. Each isolated callback owns one separate prepared input.

## Implemented contract

Add an observed-field declaration, bounded callback data, and separately owned prepared input. Preserve the existing write protection.

## Scope

The audit projection is `total` only. The example uses `observes/1` and
`Jido.Agent.Plugin.prepare/2`. Callback isolation is an API contract, not a sandbox for
untrusted BEAM code.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_10_plugin_isolation --include example --seed 0
```

This command must pass with no skipped check.

[Source](plugin_isolation.ex) · [Tests](../../../test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs)
