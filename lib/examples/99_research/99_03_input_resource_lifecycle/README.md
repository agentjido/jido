# FA-06: Plugin runtime reconstruction from committed state

Status: **Core feature required; public pull recovery works**.

Result on 2026-09-05: **1 passing checks; 1 failing acceptance checks.** All checks are enabled.

## Feature and proof

The input runtime automatically pulls current owned state after startup. After a crash it rebuilds feed B, rejects stale feed A input, and closes owned resources. Replacement Init itself has no plugin_state or state_version.

## Required change

Supply current committed owned state and its matching version in each replacement Init. Retain the working public recovery path.

## Scope

This tests Plugin runtime loss, input generation checks, and resource cleanup. It does not test a live vendor connection or duplicate event IDs. Jido.Plugin.state/1 already supplies a working application recovery mechanism.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_03_input_resource_lifecycle --include example --seed 0
```

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](runtime_reconstruction.ex) · [Tests](../../../../test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs) · [Complete result log](../../../../docs/examples/feature-acceptance-results.md)
