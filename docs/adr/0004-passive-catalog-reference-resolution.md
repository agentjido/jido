# ADR 0004: Passive Catalog reference resolution

- Status: Accepted
- Date: 2026-11-10

## Context

Flows and Agents hydrated from JSON need an explicit set of viable references.
Downstream packages need the same mechanism. Semantic kinds, inventory Views,
and revision tracking added responsibilities beyond reference registration.

## Decision

Catalog guarantees only that a value was registered under an ID and version.
Consumers validate domain roles. Remove semantic kinds, filtered Views, redundant
indexes, and Catalog revisions. Allow aliases for a value; reverse lookup uses
the first ID/version in sorted order. Reject duplicate ID/version pairs and
report both sources.

Normal DSL declarations provide registrations. Downstream modules contribute
through static manifests. Default module IDs use full module names; named
values use Provider/name. Versions default to 1. Explicit IDs preserve identity
across renames.

Discovery builds and publishes asynchronously without blocking application
startup. Callers own retries for `:catalog_not_ready`. Initial build failure is
`:catalog_build_failed`. Failed refreshes preserve the last valid Catalog.
Normal hydration uses the current Catalog on each lookup without capturing or
pinning a publication. Tests and exceptions pass an explicit Catalog.

## Consequences

This intentionally changes the pre-release Catalog and Reference APIs and
manifest shape. Codec callbacks receive an explicit Catalog or `:current`.
They must use the shared Reference and Value APIs for current lookups.
A refresh can change values between lookups in one hydration operation.
No implicit retry, snapshot protocol, or domain-kind extension system is added.

See [the guide](../../guides/data/catalog.md) and
[component contract](../components/catalog.md).

Hydration rejects registered module references when the module cannot load.
It does not defer missing-module failures to execution or compile source code.
Catalog itself continues to accept explicitly registered values without loading them.
