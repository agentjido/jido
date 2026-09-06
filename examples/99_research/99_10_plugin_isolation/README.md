# FA-02: Plugin read and prepared-input isolation

Status: **Core feature required**.

Result on 2026-09-05: **2 passing checks; 2 failing acceptance checks.** All checks are enabled.

## Feature and proof

Owned Plugin state updates successfully. An Action cannot overwrite it, and failure preserves live state. However, the audit callback receives customer_secret and the complete state. A later Plugin replaces the first Plugin's prepared input.

## Required change

Add an observed-field declaration, bounded callback data, and separately owned prepared input. Preserve the existing write protection.

## Scope

The intended audit projection is total only. Current core has no observes declaration. The enabled assertion marks that missing contract; the example does not claim to configure an existing isolation option. Callback isolation is an API contract, not a sandbox for untrusted BEAM code.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_10_plugin_isolation --include example --seed 0
```

This command returns a failing status until the stated core contract exists. Do not skip the assertion or reverse it to accept the current limitation.

[Source](plugin_isolation.ex) · [Tests](../../../test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs) · [Complete result log](../../../docs/examples/feature-acceptance-results.md)
