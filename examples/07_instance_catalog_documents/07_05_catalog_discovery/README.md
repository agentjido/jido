# 07_05 Catalog discovery

Publish one trusted package inventory as an immutable application Catalog.

## What you will learn

- Actions contribute stable IDs, versions, and schemas at compile time.
- A package can contribute other named values with a static manifest.
- Catalog refresh publishes all entries at once or keeps the old Catalog.

## Read the code

Read [the package catalog](package_catalog.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_05_catalog_discovery --warnings-as-errors`

Expected result: discovery resolves the Action and vocabulary entry. A failed
scan does not replace the last complete Catalog.

## Important behavior

Discovery is an inventory service. Finding a module does not authorize its
execution. A host application should use an application allowlist for stored
definitions.

## Limits

The test refreshes the process-wide Catalog and restores normal discovery
after each case. Packages loaded after the startup scan need an explicit
refresh.

## Core Fit and Gaps

Static package contributions and atomic publication compose through public
APIs. Catalog publication is process-wide, so integration tests that refresh
it must run serially. This is application test isolation, not a missing runtime
operation.

## Files

- [Source](package_catalog.ex)
- [Tests](package_catalog_test.exs)

Previous: [Logical identity](../07_04_logical_identity/README.md) | Next: [Portable values](../07_06_portable_values/README.md)
