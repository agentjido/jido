# FA-02: Plugin read and prepared-input isolation

Status: **Core feature required**.

Baseline on 2026-09-05: 2 passing and 2 failing checks.
As of 2026-09-07, the failing tests are temporarily skipped, with reasons.
The original assertions remain. See the [research test policy](../README.md).

## Feature and proof

Owned Plugin state updates successfully. An Action cannot overwrite it, and failure preserves live state. However, the audit callback receives customer_secret and the complete state. A later Plugin replaces the first Plugin's prepared input.

## Required change

Add an observed-field declaration, bounded callback data, and separately owned prepared input. Preserve the existing write protection.

## Scope

The intended audit projection is total only. Current core has no observes declaration. The retained assertion marks that missing contract; the example does not claim to configure an existing isolation option. Callback isolation is an API contract, not a sandbox for untrusted BEAM code.

## Run

From the jido repository:

```sh
mix test test/examples/99_research/99_10_plugin_isolation --include example --seed 0
```

This is a secondary check. The missing-contract tests remain skipped until
the feature is implemented. Do not reverse the original assertions.

[Source](../../../../examples/99_research/99_10_plugin_isolation/plugin_isolation.ex) · [Tests](plugin_isolation_test.exs)
