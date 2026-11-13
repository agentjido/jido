# 07_02 Namespaces and partitions

Use the same Agent ID safely in separate application and tenant scopes.

## What you will learn

- A stable identity is the exact `{namespace, partition, id}` tuple.
- One instance accepts only references from its bound namespace.
- Separate partitions keep state and processes independent.

## Read the code

Read [the isolation example](isolation.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_02_namespaces_and_partitions --warnings-as-errors`

Expected result: three `counter` Agents commit independent counts of 2, 1,
and 1. A cross-namespace create request fails.

## Important behavior

Namespace and partition scope identity. They do not grant access.

## Limits

This lesson uses local instances. It does not prove distributed placement or
tenant authorization.

## Files

- [Source](isolation.ex)
- [Tests](isolation_test.exs)

Previous: [Instance configuration](../07_01_instance_configuration/README.md) | Next: [Stable references](../07_03_stable_references/README.md)

