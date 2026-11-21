# 07_04 Stable Address

A stable Agent Address resolves the current conversation process after replacement.

## What you will learn

- How an Address keeps namespace, partition, and Agent identity without keeping a PID.
- How the same Address reaches restored state after process or instance replacement.
- How partitions isolate equal namespace and Agent ID pairs.
- How `Address.to_map/1` and `Address.from_map/1` transport exact versioned identity.

## Read the code

Read [the conversation Agent and Address client](stable_address.ex), then read the
behavior tests.

## Run it

```sh
mix test.examples examples/07_instance_catalog_documents/07_04_logical_identity --warnings-as-errors
```

Expected result: calls reach the correct conversation before and after process
replacement, persistence restore, and instance rebinding.

## Important behavior

Resolve the Address for each operation. Equal Agent IDs in different namespaces are
different identities. Equal namespace and ID values in different partitions
are also different identities. Rebinding a namespace to a new local Jido
instance keeps the durable identity when both instances use the same
persistence record.

The public map has exact string keys for version, namespace, partition, and ID.
Decode it with `Address.from_map/1` before use. A Address is an identifier, not a
credential.

## Limits

The test store is local and in memory. A Address does not provide cluster-wide
ownership, routing, or fencing.

## Files

- [Source](stable_address.ex)
- [Tests](stable_address_test.exs)

Previous: [Stable Addresses](../07_03_stable_addresses/README.md) |
Next: [Catalog discovery](../07_05_catalog_discovery/README.md)
