# 07 Jido Instance, Catalog, and Documents

These lessons explain application-level runtime identity and portable
definition boundaries.

1. [Instance Configuration](07_01_instance_configuration/README.md) starts a
   named Jido supervision tree with bounded runtime options.
2. [Namespaces and Partitions](07_02_namespaces_and_partitions/README.md)
   isolates equal Agent IDs by application and tenant scope.
3. [Stable References](07_03_stable_references/README.md) defines the exact
   portable Agent address.
4. [Logical Identity](07_04_logical_identity/README.md) separates one durable
   Agent identity from its current process identity.
5. [Catalog Discovery](07_05_catalog_discovery/README.md) publishes one static
   package inventory atomically.
6. [Portable Values](07_06_portable_values/README.md) rejects process-local
   values at a storage boundary.
7. [Codec Documents](07_07_codec_documents/README.md) combines trusted
   definition codecs, stable references, and document limits.
8. [Application Supervision](07_08_application_supervision/README.md) places
   Jido and application bootstrap in one host OTP tree.

Run the current chapter with:

```sh
mix test.examples examples/07_instance_catalog_documents --warnings-as-errors
```

Expected result: all instance, identity, Catalog, document, and supervision
boundaries pass without a network or private Jido runtime API.

## Limits

A stable reference is an address. It is not an authorization credential and
does not prove cluster ownership.
