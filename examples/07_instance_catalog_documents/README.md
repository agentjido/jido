# 07 Jido Instance, Catalog, and Documents

These lessons explain application-level runtime identity and portable
definition boundaries.

1. Jido instance startup and configuration remain to be added.
2. Namespace and partition isolation remain to be added as a focused lesson.
3. Stable Agent references are introduced in lesson 4.
4. [Logical Identity](07_04_logical_identity/README.md) separates one durable
   Agent identity from its current process identity.
5. Catalog discovery and package contributions remain to be added.
6. Portable values and forbidden runtime values remain to be added.
7. Codec documents, stable references, and term limits remain to be added.
8. Installed definitions and application supervision remain to be added.

Run the current chapter with:

```sh
mix test.examples examples/07_instance_catalog_documents --warnings-as-errors
```

Expected result: the same stable Agent reference resolves the current process
after process and instance replacement.

## Limits

A stable reference is an address. It is not an authorization credential and
does not prove cluster ownership.

