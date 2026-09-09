# FA-06: Plugin runtime reconstruction from committed state

Status: **Core feature implemented and proved**.

Baseline on 2026-09-05: 1 passing and 1 failing checks.
As of 2026-09-10, both checks pass and no check is skipped.

## Feature and proof

The input runtime builds its first resource from the owned `plugin_state` and
matching `state_version` in `Jido.Plugin.Init`. After a crash it rebuilds feed
B, rejects stale feed A input, and closes owned resources. It keeps the public
state-pull path for reconciliation after later commits.

## Scope

This tests Plugin runtime loss, input generation checks, and resource cleanup. It does not test a live vendor connection or duplicate event IDs. Jido.Plugin.state/1 already supplies a working application recovery mechanism.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_03_input_resource_lifecycle --include example --seed 0
```

This is a secondary passing check.

[Source](../../../../examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction.ex) · [Tests](runtime_reconstruction_test.exs)
