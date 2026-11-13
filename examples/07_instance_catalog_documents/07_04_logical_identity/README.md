# 07_04 Stable Reference

A stable Agent Ref resolves the current conversation process after replacement.

## What you will learn

- How a Ref keeps namespace, partition, and Agent identity without keeping a PID.
- How the same Ref reaches restored state after process or instance replacement.
- How partitions isolate equal namespace and Agent ID pairs.
- How `Ref.to_map/1` and `Ref.from_map/1` transport exact versioned identity.

## Read the code

Read [the conversation Agent and Ref client](stable_reference.ex), then read the
behavior tests.

## Run it

```sh
mix test.examples examples/07_instance_catalog_documents/07_04_logical_identity
```

Expected result: calls reach the correct conversation before and after process
replacement, persistence restore, and instance rebinding.

## Important behavior

Resolve the Ref for each operation. Equal Agent IDs in different namespaces are
different identities. Equal namespace and ID values in different partitions
are also different identities. Rebinding a namespace to a new local Jido
instance keeps the durable identity when both instances use the same
persistence record.

The public map has exact string keys for version, namespace, partition, and ID.
Decode it with `Ref.from_map/1` before use. A Ref is an identifier, not a
credential.

## Limits

The test store is local and in memory. A Ref does not provide cluster-wide
ownership, routing, or fencing.

## Files

- [Source](stable_reference.ex)
- [Tests](stable_reference_test.exs)

Previous: [Stable references](../07_03_stable_references/README.md) |
Next: [Catalog discovery](../07_05_catalog_discovery/README.md)
