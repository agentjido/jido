---
title: Jido.Catalog component
status: current
last-reviewed: 2026-11-10
---

# Jido.Catalog component

Catalog is a passive registry of explicitly registered values for JSON hydration.
It guarantees registration; the consumer validates the value's domain role.

| Surface | Operations |
| --- | --- |
| Build | `new/1`, `new!/1`, `from_targets/3`, `from_targets!/3` |
| Inspect registrations | `get/3`, `get_by_target/2`, `list/1` |
| References | `resolve/2`, `reference/2` |
| Discovery | `ready?/0`, `catalog/0`, `get/2`, `get_by_target/1`, `refresh/1` |

Entry owns ID, version, target, provider, and OTP application. Manifest supplies
ownership for a package contribution. IDs and versions have authoring defaults
and explicit overrides. Discovery collects normal DSL declarations and downstream
manifests, then publishes asynchronously. Failed refreshes keep the last valid
Catalog; duplicate IDs and versions reject a build with both sources.

Normal hydration uses the current publication at each lookup, without pinning.
An explicit Catalog takes precedence for tests and exceptions. Before publication,
hydration reports `:catalog_not_ready`; an initial build failure reports
`:catalog_build_failed`. Callers own retries.

Catalog has no semantic kinds, filtered Views, revision API, domain target
validation, execution authority, module loading, waits, or retry policy.

Reach assigns Catalog values to `value_model` and Discovery to `composition`.
These are dependency layers, separate from the product component tree. Existing
Covenant proof remains under `jido_action.authoring` and `jido_action.codec`.

See [Catalog guide](../../guides/data/catalog.md) and
[ADR 0004](../adr/0004-passive-catalog-reference-resolution.md).

Hydration rejects registered module references when the module cannot load.
It does not defer missing-module failures to execution or compile source code.
Catalog itself continues to accept explicitly registered values without loading them.
