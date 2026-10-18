# 11_07 External Uncertainty

Status: **Proposed outline. No executable source or tests yet.**

Prove how recovery handles an external operation whose result was not saved.

## Planned code

Publish the report through a deterministic local provider that accepts a stable
operation ID. Save intent before the provider call. Kill execution after the
provider accepts the operation but before the node result is checkpointed.
Keep provider state outside the killed BEAM for this test.

```text
save operation ID → provider accepts publication → CRASH before result save
recover → query or repeat same operation ID → one provider publication
```

## Acceptance tests to add

- Recover with the original operation ID and confirm one provider publication.
- Reject a repeated operation ID with different publication data.
- For a provider without idempotency or result lookup, retain an explicit needs-attention outcome.
- Prove that uncertain unsafe work is not dispatched automatically.
- Show that cancellation stops local work but cannot undo provider acceptance.
- Keep provider cleanup and all crash barriers in test support.

## Current evidence and gap

The [recoverable effects guide](../../../guides/recoverable-effects.md) and
[delivery example](../../10_persistence/10_07_recoverable_delivery/README.md)
provide the current application pattern. The execution integration still needs
a declared replay policy and a way to preserve uncertainty. Provider-specific
behavior belongs to the provider adapter; AI tool policy belongs to `jido_ai`.

## Limits

This proves the selected provider contract, not exactly-once arbitrary I/O.
The provider stub is a test fixture, not a production delivery service. Retries
need an explicit finite policy and must never invent a new operation ID to
conceal uncertainty.

## Run status

There is no run command for this outline. Do not add passing placeholders or
skipped tests. Add source and a focused behavior test when this stage is built.

Previous: [Durable Wait](../11_06_durable_wait/README.md) | [Durable overview](../README.md)
